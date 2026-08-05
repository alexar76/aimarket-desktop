/**
 * Patch applier for the AI Stack Migration Assistant.
 *
 * The hub returns project-specific patches inside `InvokeResult.output.patches`.
 * Because the hub may emit either unified-diff text (the canonical interchange
 * format the user previews — see docs/architecture.md "Patcher … Outputs a diff")
 * or pre-computed structural edits, this module accepts both shapes and applies
 * them with real `vscode.WorkspaceEdit` operations, then persists the files.
 *
 * The applier is strict: a hunk is only applied if its context lines match the
 * current file content exactly. If any hunk fails to locate its context, the
 * whole file is rejected and reported as a failure — never silently skipped and
 * never reported as a fake success.
 */

import * as vscode from 'vscode';

// ── Patch shapes ──────────────────────────────────────────────

/** A patch expressed as unified-diff text for a single file. */
export interface DiffPatch {
  file: string;
  diff: string;
}

/** A single range-scoped edit within a file. */
export interface RangeEdit {
  /** 0-based start line. */
  startLine: number;
  /** 0-based start character within the start line. */
  startChar?: number;
  /** 0-based end line (exclusive of trailing newline). */
  endLine: number;
  /** 0-based end character within the end line. */
  endChar?: number;
  /** Replacement text for the range. */
  newText: string;
}

/** A patch expressed as a whole-file replacement or a list of range edits. */
export interface EditPatch {
  file: string;
  /** Full replacement contents for the file. */
  newText?: string;
  /** Range-scoped edits, applied from bottom to top. */
  edits?: RangeEdit[];
}

export type Patch = DiffPatch | EditPatch;

/** Outcome of applying patches for a single file. */
export interface FileApplyResult {
  file: string;
  applied: boolean;
  reason?: string;
}

/** Aggregate outcome of a patch-apply run. */
export interface ApplyResult {
  results: FileApplyResult[];
  applied: number;
  failed: number;
}

// ── Type guards ───────────────────────────────────────────────

function isDiffPatch(p: Patch): p is DiffPatch {
  return typeof (p as DiffPatch).diff === 'string';
}

function isEditPatch(p: Patch): p is EditPatch {
  const e = p as EditPatch;
  return typeof e.newText === 'string' || Array.isArray(e.edits);
}

// ── Unified-diff parsing ──────────────────────────────────────

interface Hunk {
  /** 1-based original start line from the @@ header. */
  origStart: number;
  origLines: number;
  /** Raw hunk body lines (each prefixed with ' ', '-', '+', or '\'). */
  body: string[];
}

const HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;

/**
 * Parse the hunks out of a unified diff. Leading file headers
 * (`--- `, `+++ `, `diff `, `index `) are ignored — the target file is
 * already known from the patch object.
 */
function parseHunks(diff: string): Hunk[] {
  const lines = diff.split(/\r?\n/);
  const hunks: Hunk[] = [];
  let current: Hunk | null = null;

  for (const line of lines) {
    const header = HUNK_HEADER.exec(line);
    if (header) {
      if (current) hunks.push(current);
      current = {
        origStart: parseInt(header[1], 10),
        origLines: header[2] ? parseInt(header[2], 10) : 1,
        body: [],
      };
      continue;
    }
    if (!current) {
      // Skip diff/file headers and any preamble before the first hunk.
      continue;
    }
    // A bare empty line inside a hunk represents an empty context line.
    if (line === '') {
      current.body.push(' ');
      continue;
    }
    const tag = line[0];
    if (tag === ' ' || tag === '+' || tag === '-' || tag === '\\') {
      current.body.push(line);
    } else {
      // Anything else terminates the current hunk (e.g. a new file section).
      hunks.push(current);
      current = null;
    }
  }
  if (current) hunks.push(current);
  return hunks;
}

/**
 * Apply parsed hunks to the source lines. Returns the patched lines, or
 * `null` if any hunk's context/deletion lines do not match the source
 * exactly (in which case the file must be rejected, not partially patched).
 *
 * `source` is the file split on newlines (without line terminators). The
 * function locates each hunk by its declared original start line and falls
 * back to scanning for the context block if the declared offset has drifted.
 */
function applyHunks(source: string[], hunks: Hunk[]): string[] | null {
  // Work on a copy and track the running offset between original and
  // patched line numbers as earlier hunks add/remove lines.
  const result = source.slice();
  let offset = 0;

  for (const hunk of hunks) {
    // Lines the hunk expects to consume from the original file (context + deletions).
    const expected: string[] = [];
    for (const bl of hunk.body) {
      const tag = bl[0];
      const content = bl.slice(1);
      if (tag === ' ' || tag === '-') expected.push(content);
      // '+' lines are additions (not present in original); '\' is the
      // "No newline at end of file" marker — both are ignored here.
    }

    const located = locateHunk(result, hunk.origStart - 1 + offset, expected);
    if (located < 0) return null;

    // Build the replacement block from context + additions, in order.
    const replacement: string[] = [];
    for (const bl of hunk.body) {
      const tag = bl[0];
      const content = bl.slice(1);
      if (tag === ' ' || tag === '+') replacement.push(content);
      // '-' lines are removed; '\' markers are dropped.
    }

    result.splice(located, expected.length, ...replacement);
    offset += replacement.length - expected.length;
  }

  return result;
}

/**
 * Find the index in `lines` where `expected` matches exactly. Tries the
 * preferred index first, then scans outward so small line-number drift in
 * the diff header does not cause a spurious failure. Returns -1 if no exact
 * match exists.
 */
function locateHunk(lines: string[], preferred: number, expected: string[]): number {
  if (expected.length === 0) {
    // Pure insertion hunk: clamp the anchor into range.
    if (preferred < 0) return 0;
    if (preferred > lines.length) return lines.length;
    return preferred;
  }

  const matchesAt = (idx: number): boolean => {
    if (idx < 0 || idx + expected.length > lines.length) return false;
    for (let k = 0; k < expected.length; k++) {
      if (lines[idx + k] !== expected[k]) return false;
    }
    return true;
  };

  const clampedPreferred = Math.max(0, Math.min(preferred, lines.length));
  if (matchesAt(clampedPreferred)) return clampedPreferred;

  const maxStart = lines.length - expected.length;
  for (let dist = 1; dist <= lines.length; dist++) {
    const before = clampedPreferred - dist;
    const after = clampedPreferred + dist;
    if (after <= maxStart && matchesAt(after)) return after;
    if (before >= 0 && matchesAt(before)) return before;
    if (before < 0 && after > maxStart) break;
  }
  return -1;
}

// ── File application ──────────────────────────────────────────

/**
 * Detect the dominant line terminator of a document so the patched text we
 * write back matches the file's existing convention.
 */
function detectEol(doc: vscode.TextDocument): string {
  return doc.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n';
}

/**
 * Resolve a patch's `file` field to a workspace URI. Absolute paths are used
 * as-is; relative paths are resolved against the first workspace folder.
 */
function resolveUri(file: string): vscode.Uri {
  if (file.startsWith('/') || /^[a-zA-Z]:[\\/]/.test(file)) {
    return vscode.Uri.file(file);
  }
  const folders = vscode.workspace.workspaceFolders;
  if (folders && folders.length > 0) {
    return vscode.Uri.joinPath(folders[0].uri, file);
  }
  return vscode.Uri.file(file);
}

/** Compute the full replacement text for a diff patch, or null on failure. */
function applyDiffToText(original: string, diff: string, eol: string): string | null {
  const hunks = parseHunks(diff);
  if (hunks.length === 0) return null;

  // Split without dropping a meaningful trailing empty line.
  const hadTrailingNewline = /\r?\n$/.test(original);
  const source = original.replace(/\r?\n$/, '').split(/\r?\n/);
  const patched = applyHunks(source, hunks);
  if (patched === null) return null;

  let out = patched.join(eol);
  if (hadTrailingNewline) out += eol;
  return out;
}

/**
 * Apply a single patch object to its target document via a WorkspaceEdit and
 * save the file. Returns whether the edit was successfully applied.
 */
async function applyOne(patch: Patch): Promise<FileApplyResult> {
  const uri = resolveUri(patch.file);

  let doc: vscode.TextDocument;
  try {
    doc = await vscode.workspace.openTextDocument(uri);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return { file: patch.file, applied: false, reason: `cannot open file: ${msg}` };
  }

  const edit = new vscode.WorkspaceEdit();
  const eol = detectEol(doc);
  const fullRange = new vscode.Range(
    new vscode.Position(0, 0),
    doc.lineAt(Math.max(doc.lineCount - 1, 0)).range.end
  );

  if (isDiffPatch(patch)) {
    const newText = applyDiffToText(doc.getText(), patch.diff, eol);
    if (newText === null) {
      return {
        file: patch.file,
        applied: false,
        reason: 'diff did not apply cleanly (context mismatch)',
      };
    }
    if (newText === doc.getText()) {
      // Already at the target state — nothing to write, but not a failure.
      return { file: patch.file, applied: true, reason: 'no changes (already applied)' };
    }
    edit.replace(uri, fullRange, newText);
  } else if (isEditPatch(patch)) {
    if (typeof patch.newText === 'string') {
      if (patch.newText === doc.getText()) {
        return { file: patch.file, applied: true, reason: 'no changes (already applied)' };
      }
      edit.replace(uri, fullRange, patch.newText);
    } else if (Array.isArray(patch.edits) && patch.edits.length > 0) {
      // Apply range edits; WorkspaceEdit handles overlapping/ordering safely,
      // but we validate ranges against the document up front.
      for (const e of patch.edits) {
        const start = new vscode.Position(
          Math.max(0, e.startLine),
          Math.max(0, e.startChar ?? 0)
        );
        const end = new vscode.Position(
          Math.max(0, e.endLine),
          Math.max(0, e.endChar ?? 0)
        );
        if (start.line >= doc.lineCount || end.line >= doc.lineCount) {
          return {
            file: patch.file,
            applied: false,
            reason: `edit range out of bounds (line ${e.startLine}-${e.endLine})`,
          };
        }
        edit.replace(uri, new vscode.Range(start, end), e.newText);
      }
    } else {
      return { file: patch.file, applied: false, reason: 'empty edit patch' };
    }
  } else {
    return { file: patch.file, applied: false, reason: 'unrecognized patch shape' };
  }

  const ok = await vscode.workspace.applyEdit(edit);
  if (!ok) {
    return { file: patch.file, applied: false, reason: 'WorkspaceEdit rejected by editor' };
  }

  // Persist so the on-disk file reflects the migration before tests run.
  const saved = await doc.save();
  if (!saved) {
    return { file: patch.file, applied: false, reason: 'file edited but failed to save' };
  }

  return { file: patch.file, applied: true };
}

/**
 * Normalize the raw `output.patches` value into a typed `Patch[]`. Filters out
 * entries that have neither a `file` nor any applicable payload.
 */
export function normalizePatches(raw: unknown): Patch[] {
  if (!Array.isArray(raw)) return [];
  const patches: Patch[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== 'object') continue;
    const obj = entry as Record<string, unknown>;
    if (typeof obj.file !== 'string' || obj.file.length === 0) continue;
    if (typeof obj.diff === 'string') {
      patches.push({ file: obj.file, diff: obj.diff });
    } else if (typeof obj.newText === 'string') {
      patches.push({ file: obj.file, newText: obj.newText });
    } else if (Array.isArray(obj.edits)) {
      patches.push({ file: obj.file, edits: obj.edits as RangeEdit[] });
    }
  }
  return patches;
}

/**
 * Apply a list of patches to the workspace. Each file is applied
 * independently and reported honestly; a failure on one file does not abort
 * the others, but is surfaced in the returned result.
 */
export async function applyPatches(patches: Patch[]): Promise<ApplyResult> {
  const results: FileApplyResult[] = [];
  for (const patch of patches) {
    try {
      results.push(await applyOne(patch));
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      results.push({ file: patch.file, applied: false, reason: msg });
    }
  }
  const applied = results.filter((r) => r.applied).length;
  return { results, applied, failed: results.length - applied };
}
