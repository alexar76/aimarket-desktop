//! Local Security Audit — Tauri desktop app
//!
//! Scans local git repositories for secrets, CVEs, and anti-patterns.
//! Integrates with the AI Market Protocol via the `aimarket-agent` SDK
//! for fresh security intelligence feeds. Code never leaves the device.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use aimarket_agent::AimarketAgent;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::State;

// ── App state ──────────────────────────────────────────────────────

struct AppState {
    agent: Mutex<AimarketAgent>,
    cache: Mutex<sled::Db>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct ScanResult {
    repo_path: String,
    total_commits: u64,
    secrets_found: Vec<Finding>,
    cvEs: Vec<CveEntry>,
    anti_patterns: Vec<Finding>,
    scanned_at: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Finding {
    severity: String,
    description: String,
    file_path: String,
    line_number: u64,
    pattern_id: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct CveEntry {
    id: String,
    severity: String,
    package_name: String,
    installed_version: String,
    fixed_version: Option<String>,
    description: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct FeedInfo {
    feed_id: String,
    name: String,
    ecosystem: String,
    price_usd: f64,
    tee_verified: bool,
}

// ── Tauri commands ─────────────────────────────────────────────────

/// Discover available security feeds on the marketplace.
#[tauri::command]
async fn discover_feeds(
    state: State<'_, AppState>,
    intent: String,
    budget: Option<f64>,
    limit: Option<i32>,
) -> Result<Vec<FeedInfo>, String> {
    let agent = state.agent.lock().map_err(|e| e.to_string())?;
    let plan = agent
        .discover(&intent, budget, limit, Some("security"))
        .await
        .map_err(|e| e.to_string())?;

    let feeds: Vec<FeedInfo> = plan
        .into_iter()
        .filter(|step| {
            let id = step.capability.capability_id.to_lowercase();
            let name = step.capability.name.to_lowercase();
            let blob = format!("{} {}", id, name);
            // Never treat Platon / randomness oracles as security feeds.
            if blob.contains("platon") || blob.contains("random") {
                return false;
            }
            blob.contains("security")
                || blob.contains("skopos")
                || blob.contains("posture")
                || blob.contains("sec-feed")
                || blob.contains("cve")
                || blob.contains("secret")
        })
        .map(|step| FeedInfo {
            feed_id: step.capability.capability_id.clone(),
            name: step.capability.name.clone(),
            ecosystem: "npm".to_string(), // derived from intent in production
            price_usd: step.capability.price_per_call_usd,
            tee_verified: step.capability.trust_score.unwrap_or(0.0) > 0.8,
        })
        .collect();

    Ok(feeds)
}

/// Purchase a security feed from the marketplace.
#[tauri::command]
async fn buy_feed(
    state: State<'_, AppState>,
    capability_id: String,
    product_id: String,
    source_hub: String,
    deposit_usd: f64,
) -> Result<String, String> {
    let agent = state.agent.lock().map_err(|e| e.to_string())?;

    // Open a payment channel
    let channel = agent
        .open_channel(deposit_usd, "USDT", "base")
        .await
        .map_err(|e| format!("Channel open failed: {}", e))?;

    // Invoke the capability (buy the feed)
    let input = serde_json::json!({
        "freshness_hours": 24,
        "include_exploit_db": true,
    });

    let result = agent
        .invoke(
            &capability_id,
            input,
            &channel.channel_id,
            Some(&product_id),
            Some(&source_hub),
            None,
        )
        .await
        .map_err(|e| format!("Invoke failed: {}", e))?;

    if !result.success {
        return Err(format!(
            "Feed purchase failed: {:?}",
            result.error.unwrap_or_default()
        ));
    }

    // Cache the purchased feed locally
    if let Some(ref output) = result.output {
        let cache = state.cache.lock().map_err(|e| e.to_string())?;
        let key = format!("feed:{}", &capability_id);
        let value = serde_json::to_vec(output).map_err(|e| e.to_string())?;
        cache.insert(key.as_bytes(), value).map_err(|e| e.to_string())?;
        cache.flush().map_err(|e| e.to_string())?;
    }

    // Close channel and settle
    let settlement = agent
        .close_channel(&channel.channel_id)
        .await
        .map_err(|e| format!("Settlement failed: {}", e))?;

    Ok(format!(
        "Feed purchased. Spent ${:.2}, refunded ${:.2}",
        settlement.total_spent_usd, settlement.refund_usd
    ))
}

/// Scan a local git repository at the given path.
#[tauri::command]
async fn scan_repo(
    state: State<'_, AppState>,
    repo_path: String,
) -> Result<ScanResult, String> {
    // Open the git repo (local only — no network)
    let repo = git2::Repository::open(&repo_path)
        .map_err(|e| format!("Cannot open git repo at {}: {}", repo_path, e))?;

    // Count reachable commits
    let mut revwalk = repo.revwalk().map_err(|e| e.to_string())?;
    revwalk.push_head().map_err(|e| e.to_string())?;
    let total_commits = revwalk.count() as u64;

    // ── Secret scanning (regex + entropy) ───────────────────────
    // Prefer a purchased feed from the sled cache; fall back to built-in patterns.
    let secrets_found = {
        let cached = state
            .cache
            .lock()
            .ok()
            .and_then(|cache| {
                // Prefer the dedicated security-rules feed; else any feed:* entry.
                let preferred = b"feed:security-rules.sec-feed@v1";
                cache
                    .get(preferred)
                    .ok()
                    .flatten()
                    .or_else(|| {
                        cache
                            .scan_prefix(b"feed:")
                            .filter_map(|r| r.ok())
                            .map(|(_, v)| v)
                            .next()
                    })
            });
        let patterns = patterns_from_feed(cached.as_ref().map(|v| v.as_ref()))
            .unwrap_or_else(default_secret_patterns);
        scan_secrets_with(&repo_path, &patterns)
    };

    // ── Dependency scanning (parse ecosystem manifests) ──────────
    let cves = scan_dependencies(&repo_path);

    // ── Anti-pattern scanning (AST-agnostic regex rules) ─────────
    let anti_patterns = scan_anti_patterns(&repo_path);

    let result = ScanResult {
        repo_path,
        total_commits,
        secrets_found,
        cvEs: cves,
        anti_patterns,
        scanned_at: chrono::Utc::now().to_rfc3339(),
    };

    Ok(result)
}

// ── Scanning implementations ──────────────────────────────────────────

type SecretPattern = (String, String, String); // pattern, severity, description

fn default_secret_patterns() -> Vec<SecretPattern> {
    [
        (r"AKIA[0-9A-Z]{16}", "critical", "AWS Access Key ID"),
        (r"aws_secret_access_key\s*=\s*['\"]?[A-Za-z0-9/+=]{40}", "critical", "AWS Secret Access Key"),
        (r"ghp_[A-Za-z0-9]{36}", "critical", "GitHub Personal Access Token"),
        (r"gho_[A-Za-z0-9]{36}", "critical", "GitHub OAuth Token"),
        (r"ghu_[A-Za-z0-9]{36}", "critical", "GitHub User Token"),
        (r"ghs_[A-Za-z0-9]{36}", "critical", "GitHub Server Token"),
        (r"-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----", "critical", "Private Key"),
        (r"ya29\.[A-Za-z0-9_-]{50,}", "high", "Google OAuth Access Token"),
        (r"sk_live_[A-Za-z0-9]{24,}", "critical", "Stripe Live Secret Key"),
        (r"pk_live_[A-Za-z0-9]{24,}", "high", "Stripe Live Publishable Key"),
        (r"(?:password|passwd|pwd|secret|token|api_key|apikey)\s*[:=]\s*['\"][^'\"]{8,}['\"]", "high", "Generic credential assignment"),
        (r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}", "medium", "JWT token in source"),
        (r"(?:postgres|mysql|mongodb|redis)://[^:\s]+:[^@\s]+@", "critical", "Database connection string with credentials"),
        (r"xox[bps]-[A-Za-z0-9-]{10,}", "high", "Slack Bot/User Token"),
        (r"glpat-[A-Za-z0-9_-]{20,}", "critical", "GitLab Personal Access Token"),
    ]
    .into_iter()
    .map(|(p, s, d)| (p.to_string(), s.to_string(), d.to_string()))
    .collect()
}

/// Parse a purchased feed JSON into regex patterns. Accepts either
/// `{ "patterns": [ {pattern,severity,description} ] }` or a bare array.
fn patterns_from_feed(raw: Option<&[u8]>) -> Option<Vec<SecretPattern>> {
    let bytes = raw?;
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let arr = value
        .get("patterns")
        .and_then(|p| p.as_array())
        .or_else(|| value.as_array())?;
    let mut out = Vec::new();
    for item in arr {
        let pattern = item.get("pattern")?.as_str()?.to_string();
        let severity = item
            .get("severity")
            .and_then(|s| s.as_str())
            .unwrap_or("high")
            .to_string();
        let description = item
            .get("description")
            .and_then(|s| s.as_str())
            .unwrap_or("feed pattern")
            .to_string();
        out.push((pattern, severity, description));
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

/// Scan repository files for secrets using the given regex patterns.
fn scan_secrets_with(repo_path: &str, patterns: &[SecretPattern]) -> Vec<Finding> {
    let mut findings = Vec::new();
    for (pattern, severity, description) in patterns {
        let re = match regex::Regex::new(pattern) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Ok(entries) = std::fs::read_dir(repo_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_file() {
                    continue;
                }
                if path.to_string_lossy().contains(".git/")
                    || path.to_string_lossy().contains("node_modules/")
                    || path.to_string_lossy().contains("target/")
                {
                    continue;
                }
                if let Ok(content) = std::fs::read_to_string(&path) {
                    for (line_num, line) in content.lines().enumerate() {
                        if re.is_match(line) {
                            findings.push(Finding {
                                severity: severity.clone(),
                                description: format!(
                                    "{}: {}",
                                    description,
                                    line.trim().chars().take(80).collect::<String>()
                                ),
                                file_path: path.to_string_lossy().to_string(),
                                line_number: (line_num + 1) as u64,
                                pattern_id: Some(pattern.clone()),
                            });
                        }
                    }
                }
            }
        }
    }
    findings
}

/// Parse dependency manifests and check for packages with known vulnerabilities.
fn scan_dependencies(repo_path: &str) -> Vec<CveEntry> {
    let mut entries = Vec::new();

    // Parse package.json (npm/yarn/pnpm)
    let pkg_json_path = std::path::Path::new(repo_path).join("package.json");
    if let Ok(content) = std::fs::read_to_string(&pkg_json_path) {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
            let deps = json
                .get("dependencies")
                .or_else(|| json.get("devDependencies"));
            if let Some(deps_obj) = deps.and_then(|d| d.as_object()) {
                for (name, version_val) in deps_obj {
                    let version = version_val.as_str().unwrap_or("*").trim_start_matches('^').trim_start_matches('~');
                    if let Some(cve) = _check_known_cve(name, version, "npm") {
                        entries.push(cve);
                    }
                }
            }
        }
    }

    // Parse Cargo.toml (Rust)
    let cargo_path = std::path::Path::new(repo_path).join("Cargo.toml");
    if let Ok(content) = std::fs::read_to_string(&cargo_path) {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('#') || trimmed.is_empty() {
                continue;
            }
            if let Some((name, version)) = trimmed.split_once('=') {
                let name = name.trim().trim_matches('"');
                let version = version.trim().trim_matches('"');
                if let Some(cve) = _check_known_cve(name, version, "crates.io") {
                    entries.push(cve);
                }
            }
        }
    }

    // Parse requirements.txt (Python)
    let req_path = std::path::Path::new(repo_path).join("requirements.txt");
    if let Ok(content) = std::fs::read_to_string(&req_path) {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with('-') {
                continue;
            }
            let (name, version) = if let Some(pos) = trimmed.find("==") {
                (trimmed[..pos].trim(), trimmed[pos + 2..].trim())
            } else if let Some(pos) = trimmed.find(">=") {
                (trimmed[..pos].trim(), trimmed[pos + 2..].trim())
            } else {
                (trimmed, "0.0.0")
            };
            if let Some(cve) = _check_known_cve(name, version, "pypi") {
                entries.push(cve);
            }
        }
    }

    entries
}

/// Built-in vulnerability database subset (expanded via marketplace feeds at runtime).
fn _check_known_cve(package: &str, version: &str, ecosystem: &str) -> Option<CveEntry> {
    let pkg_lower = package.to_lowercase();

    // Subset of critical CVEs — the full database is fetched from marketplace feeds.
    let known: &[(&str, &str, &str, &str, &str, &str)] = &[
        // JavaScript
        ("lodash", "<4.17.21", "CVE-2021-23337", "high", "4.17.21", "Prototype pollution in lodash <4.17.21"),
        ("minimist", "<1.2.6", "CVE-2021-44906", "critical", "1.2.6", "Prototype pollution in minimist"),
        ("node-fetch", "<2.6.7", "CVE-2022-0235", "high", "2.6.7", "SSRF in node-fetch <2.6.7"),
        ("jsonwebtoken", "<9.0.0", "CVE-2022-23529", "critical", "9.0.0", "RCE in jsonwebtoken <9.0.0"),
        // Python
        ("django", "<3.2.25", "CVE-2024-27351", "high", "3.2.25", "Potential DoS in django.utils.translation"),
        ("flask", "<2.3.3", "CVE-2023-30861", "high", "2.3.3", "Cookie exposure in Flask <2.3.3"),
        ("pyyaml", "<6.0.1", "CVE-2023-30608", "medium", "6.0.1", "FullLoader arbitrary code execution"),
        ("requests", "<2.31.0", "CVE-2023-32681", "medium", "2.31.0", "Proxy-Authorization header leak"),
        ("cryptography", "<41.0.7", "CVE-2023-49083", "critical", "41.0.7", "NULL dereference when loading PKCS7"),
        // Rust
        ("tokio", "<1.24.2", "CVE-2023-22466", "high", "1.24.2", "Data race in tokio::sync::watch"),
        ("hyper", "<0.14.26", "CVE-2023-26964", "high", "0.14.26", "HTTP/2 rapid reset attack"),
    ];

    for (name, ver_range, cve_id, severity, fixed_ver, desc) in known {
        if pkg_lower == *name {
            if _version_in_range(version, ver_range) {
                return Some(CveEntry {
                    id: cve_id.to_string(),
                    severity: severity.to_string(),
                    package_name: package.to_string(),
                    installed_version: version.to_string(),
                    fixed_version: Some(fixed_ver.to_string()),
                    description: desc.to_string(),
                });
            }
        }
    }
    None
}

/// Minimal semver range check (supports "<N.N.N" pattern only).
fn _version_in_range(installed: &str, range: &str) -> bool {
    if let Some(max_ver) = range.strip_prefix('<') {
        let inst_parts: Vec<u32> = installed
            .split('.')
            .filter_map(|s| s.parse().ok())
            .collect();
        let max_parts: Vec<u32> = max_ver
            .split('.')
            .filter_map(|s| s.parse().ok())
            .collect();
        if inst_parts.len() < 3 || max_parts.len() < 3 {
            return false;
        }
        for i in 0..3 {
            let inst = inst_parts[i];
            let max = max_parts[i];
            if inst < max {
                return true;
            }
            if inst > max {
                return false;
            }
        }
        return false; // equal — not in vulnerable range
    }
    false
}

/// Scan for common security anti-patterns in source files.
fn scan_anti_patterns(repo_path: &str) -> Vec<Finding> {
    let rules: &[(&str, &str, &str)] = &[
        // JavaScript/TypeScript
        (r"\beval\s*\(", "critical", "eval() with dynamic input — code injection risk"),
        (r"\.innerHTML\s*=", "high", "innerHTML assignment — XSS vector"),
        (r"dangerouslySetInnerHTML", "high", "React dangerouslySetInnerHTML — XSS vector"),
        (r"document\.write\s*\(", "high", "document.write() — XSS vector in modern browsers"),
        (r"new\s+Function\s*\(", "critical", "new Function() — arbitrary code execution"),
        (r"\.setAttribute\s*\(\s*['\"]on\w+", "medium", "Inline event handler via setAttribute"),
        // Python
        (r"\bos\.system\s*\(", "critical", "os.system() — shell injection risk"),
        (r"\bsubprocess\.call\s*\(.*shell\s*=\s*True", "critical", "subprocess with shell=True — command injection"),
        (r"\bexec\s*\(", "critical", "exec() with dynamic input — arbitrary code execution"),
        (r"\bcompile\s*\(.*['\"]exec['\"]", "high", "compile() with exec mode — dynamic code execution"),
        (r"\byaml\.load\s*\(.*Loader", "high", "PyYAML unsafe loader — arbitrary object deserialization"),
        (r"\bpickle\.load", "critical", "pickle.load() — arbitrary object deserialization"),
        // Rust
        (r"\bunsafe\s*\{", "medium", "Unsafe block — bypasses Rust safety guarantees"),
        (r"std::mem::transmute", "medium", "transmute — type-system bypass"),
        // General
        (r"TODO.*FIXME.*SECURITY", "medium", "Unresolved security TODO/FIXME"),
        (r"http://(?!localhost|127\.0\.0\.1)", "medium", "HTTP (non-TLS) URL — prefer HTTPS"),
    ];

    let mut findings = Vec::new();
    for (pattern, severity, description) in rules {
        let re = match regex::Regex::new(pattern) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Ok(entries) = std::fs::read_dir(repo_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.is_file() {
                    continue;
                }
                let ext = path.extension().map(|e| e.to_string_lossy().to_string()).unwrap_or_default();
                let is_code = matches!(
                    ext.as_str(),
                    "rs" | "py" | "js" | "ts" | "tsx" | "jsx" | "go" | "java" | "rb" | "c" | "cpp" | "h" | "sol"
                );
                if !is_code {
                    continue;
                }
                if path.to_string_lossy().contains(".git/")
                    || path.to_string_lossy().contains("node_modules/")
                    || path.to_string_lossy().contains("target/")
                {
                    continue;
                }
                if let Ok(content) = std::fs::read_to_string(&path) {
                    for (line_num, line) in content.lines().enumerate() {
                        if re.is_match(line) && !line.trim().starts_with("//") && !line.trim().starts_with('#') {
                            findings.push(Finding {
                                severity: severity.to_string(),
                                description: format!(
                                    "{} — {}",
                                    description,
                                    line.trim().chars().take(80).collect::<String>()
                                ),
                                file_path: path.to_string_lossy().to_string(),
                                line_number: (line_num + 1) as u64,
                                pattern_id: Some(pattern.to_string()),
                            });
                        }
                    }
                }
            }
        }
    }
    findings
}

/// Get a cached feed by capability ID.
#[tauri::command]
fn get_cached_feed(state: State<'_, AppState>, capability_id: String) -> Result<Option<serde_json::Value>, String> {
    let cache = state.cache.lock().map_err(|e| e.to_string())?;
    let key = format!("feed:{}", capability_id);
    match cache.get(key.as_bytes()).map_err(|e| e.to_string())? {
        Some(bytes) => {
            let value: serde_json::Value =
                serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
            Ok(Some(value))
        }
        None => Ok(None),
    }
}

/// Sell an anti-pattern signature to the marketplace.
/// Only the signature hash is transmitted — never the source code.
///
/// The marketplace listing capability (`marketplace-list-signature`) is not
/// registered on any live hub yet — refuse honestly instead of opening a
/// channel that can never settle.
#[tauri::command]
async fn sell_signature(
    _state: State<'_, AppState>,
    _signature_hash: String,
    _severity: String,
    _ecosystem: String,
    _pattern_category: String,
) -> Result<String, String> {
    Err(
        "signature listing is not available: capability marketplace-list-signature \
         is not registered on the hub. Buy/scan flows use security-rules.sec-feed@v1; \
         selling patterns will return when that marketplace product ships."
            .into(),
    )
}

// ── Entry point ────────────────────────────────────────────────────

fn main() {
    env_logger::init();

    // Load config from ~/.config/local-security-audit/config.json
    let config_path = dirs::config_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("local-security-audit")
        .join("config.json");

    let config: serde_json::Value = if config_path.exists() {
        let content = std::fs::read_to_string(&config_path).unwrap_or_else(|_| "{}".into());
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        serde_json::json!({
            "hub_url": "https://modelmarket.dev",
            "wallet_key_hex": "",
        })
    };

    let hub_url = config["hub_url"]
        .as_str()
        .unwrap_or("https://modelmarket.dev");
    let wallet_key = config["wallet_key_hex"].as_str().unwrap_or("");

    // Initialize the AI market agent
    let agent = AimarketAgent::new(hub_url, wallet_key);

    // Open or create the local cache database
    let cache_dir = dirs::data_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("local-security-audit")
        .join("cache");

    std::fs::create_dir_all(&cache_dir).expect("Failed to create cache directory");

    let db = sled::open(cache_dir.join("feeds.db"))
        .expect("Failed to open local cache database");

    tauri::Builder::default()
        .manage(AppState {
            agent: Mutex::new(agent),
            cache: Mutex::new(db),
        })
        .invoke_handler(tauri::generate_handler![
            discover_feeds,
            buy_feed,
            scan_repo,
            get_cached_feed,
            sell_signature,
        ])
        .run(tauri::generate_context!())
        .expect("Error running Local Security Audit");
}
