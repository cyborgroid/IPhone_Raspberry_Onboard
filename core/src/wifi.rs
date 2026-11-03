//! Wi-Fi spatial sensing: turns `iw` scan output into a description of the
//! surroundings, using no GPS and no central server.
//!
//! RSSI says how strong an AP is, not where it is, so this reports density and
//! change over time. It cannot produce a bearing. Scan results stay in memory;
//! neighbours' BSSIDs are never written to disk.

use serde::Serialize;
use std::collections::{BTreeMap, HashSet};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AccessPoint {
    /// Hash of the BSSID: stable across scans so the radar view can keep a dot
    /// in place, without handing the UI a hardware address.
    pub id: u64,
    pub ssid: String,
    pub freq_mhz: u32,
    pub channel: u32,
    pub rssi_dbm: f32,
    #[serde(skip)]
    pub bssid: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct SpatialReport {
    pub ap_count: usize,
    pub mean_rssi_dbm: Option<f32>,
    pub density: &'static str,
    /// Channel number to AP count.
    pub channels: BTreeMap<u32, usize>,
    /// Jaccard similarity with the previous scan, 0..=1. None on the first scan.
    pub similarity: Option<f32>,
    pub environment: &'static str,
    pub access_points: Vec<AccessPoint>,
}

pub fn channel_of(freq_mhz: u32) -> u32 {
    match freq_mhz {
        2484 => 14,
        2412..=2472 => (freq_mhz - 2407) / 5,
        5150..=5895 => (freq_mhz - 5000) / 5,
        5955..=7115 => (freq_mhz - 5950) / 5,
        _ => 0,
    }
}

/// `iw` prints non-ASCII SSID bytes as `\xNN`, so Korean names arrive escaped.
fn decode_ssid(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && bytes.get(i + 1) == Some(&b'x') && i + 3 < bytes.len() {
            if let Ok(b) = u8::from_str_radix(&raw[i + 2..i + 4], 16) {
                out.push(b);
                i += 4;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn id_of(bssid: &str) -> u64 {
    let mut h = DefaultHasher::new();
    bssid.hash(&mut h);
    // Keep within 2^53 so the JSON number survives a double on the UI side.
    h.finish() >> 11
}

pub fn parse_iw_scan(output: &str) -> Vec<AccessPoint> {
    let mut aps = Vec::new();
    let mut cur: Option<AccessPoint> = None;
    for line in output.lines() {
        if let Some(rest) = line.strip_prefix("BSS ") {
            aps.extend(cur.take());
            let bssid = rest.split(['(', ' ']).next().unwrap_or("").to_lowercase();
            cur = Some(AccessPoint {
                id: id_of(&bssid),
                bssid,
                ssid: String::new(),
                freq_mhz: 0,
                channel: 0,
                rssi_dbm: -100.0,
            });
            continue;
        }
        let Some(ap) = cur.as_mut() else { continue };
        let t = line.trim_start();
        if let Some(v) = t.strip_prefix("freq: ") {
            // iw >= 6 prints "2412.0", older versions "2412".
            ap.freq_mhz = v.trim().parse::<f32>().unwrap_or(0.0) as u32;
            ap.channel = channel_of(ap.freq_mhz);
        } else if let Some(v) = t.strip_prefix("signal: ") {
            let dbm = v.split_whitespace().next().unwrap_or("");
            ap.rssi_dbm = dbm.parse().unwrap_or(-100.0);
        } else if ap.ssid.is_empty() {
            if let Some(v) = t.strip_prefix("SSID: ") {
                ap.ssid = decode_ssid(v);
            }
        }
    }
    aps.extend(cur);
    aps
}

fn density_of(ap_count: usize) -> &'static str {
    match ap_count {
        0 => "none",
        1..=4 => "sparse",
        5..=19 => "moderate",
        _ => "dense",
    }
}

pub fn analyze(aps: Vec<AccessPoint>, previous: Option<&[AccessPoint]>) -> SpatialReport {
    let mut channels = BTreeMap::new();
    for ap in &aps {
        *channels.entry(ap.channel).or_insert(0) += 1;
    }
    let mean_rssi_dbm = (!aps.is_empty())
        .then(|| aps.iter().map(|a| a.rssi_dbm).sum::<f32>() / aps.len() as f32);
    let similarity = previous.map(|prev| {
        let a: HashSet<&str> = aps.iter().map(|x| x.bssid.as_str()).collect();
        let b: HashSet<&str> = prev.iter().map(|x| x.bssid.as_str()).collect();
        let union = a.union(&b).count();
        if union == 0 { 1.0 } else { a.intersection(&b).count() as f32 / union as f32 }
    });
    let environment = match similarity {
        None => "unknown",
        Some(s) if s >= 0.6 => "stationary",
        Some(s) if s >= 0.25 => "changing",
        Some(_) => "moved",
    };
    SpatialReport {
        ap_count: aps.len(),
        mean_rssi_dbm,
        density: density_of(aps.len()),
        channels,
        similarity,
        environment,
        access_points: aps,
    }
}

/// `nmcli -t` output: `BSSID:SSID:FREQ:SIGNAL`, with colons inside fields escaped as
/// `\\:`. NetworkManager reports signal as a percentage, converted here to an
/// approximate dBm with its own formula.
pub fn parse_nmcli(output: &str) -> Vec<AccessPoint> {
    output
        .lines()
        .filter_map(|line| {
            let mut fields = Vec::new();
            let mut field = String::new();
            let mut chars = line.chars();
            while let Some(c) = chars.next() {
                match c {
                    '\\' => field.extend(chars.next()),
                    ':' => fields.push(std::mem::take(&mut field)),
                    _ => field.push(c),
                }
            }
            fields.push(field);
            let [bssid, ssid, freq, signal] = <[String; 4]>::try_from(fields).ok()?;
            let bssid = bssid.to_lowercase();
            let freq_mhz: u32 = freq.split_whitespace().next()?.parse().ok()?;
            let percent: f32 = signal.parse().ok()?;
            Some(AccessPoint {
                id: id_of(&bssid),
                bssid,
                ssid,
                freq_mhz,
                channel: channel_of(freq_mhz),
                rssi_dbm: percent / 2.0 - 100.0,
            })
        })
        .collect()
}

fn run(program: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new("timeout")
        .arg("20")
        .arg(program)
        .args(args)
        .output()
        .map_err(|e| format!("{program}: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_owned())
    }
}

/// Actively scans with `iw`, then falls back to its cached results for when another
/// client (NetworkManager, usually) holds the radio or we lack CAP_NET_ADMIN, and
/// finally to `nmcli`, which needs neither `iw` nor any privilege.
pub fn scan(interface: &str) -> Result<Vec<AccessPoint>, String> {
    let iw = run("iw", &["dev", interface, "scan"])
        .or_else(|_| run("iw", &["dev", interface, "scan", "dump"]))
        .map(|text| parse_iw_scan(&text));
    iw.or_else(|iw_error| {
        run(
            "nmcli",
            &["-t", "-f", "BSSID,SSID,FREQ,SIGNAL", "device", "wifi", "list", "ifname", interface],
        )
        .map(|text| parse_nmcli(&text))
        .map_err(|nmcli_error| format!("{iw_error}; {nmcli_error}"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
BSS aa:bb:cc:00:11:22(on wlan0) -- associated
\tlast seen: 1 ms ago
\tTSF: 1 usec (0d, 00:00:00)
\tfreq: 2437.0
\tbeacon interval: 100 TUs
\tsignal: -43.00 dBm
\tSSID: home-net
\tDS Parameter set: channel 6
BSS AA:BB:CC:33:44:55(on wlan0)
\tfreq: 5180
\tsignal: -71.50 dBm
\tSSID: \\xec\\x9c\\xa0\\xeb\\x8b\\x88
\tExtended Tag: SSID: not-this-one
BSS aa:bb:cc:66:77:88(on wlan0)
\tfreq: 5955
\tsignal: -80.00 dBm
\tSSID: 
";

    #[test]
    fn parses_iw_output_including_decimal_freq_and_korean_ssid() {
        let aps = parse_iw_scan(SAMPLE);
        assert_eq!(aps.len(), 3);
        assert_eq!((aps[0].ssid.as_str(), aps[0].channel, aps[0].rssi_dbm), ("home-net", 6, -43.0));
        assert_eq!((aps[1].ssid.as_str(), aps[1].channel, aps[1].rssi_dbm), ("유니", 36, -71.5));
        assert_eq!(aps[1].bssid, "aa:bb:cc:33:44:55");
        assert_eq!((aps[2].ssid.as_str(), aps[2].channel), ("", 1));
    }

    #[test]
    fn empty_output_is_no_access_points() {
        assert!(parse_iw_scan("").is_empty());
    }

    #[test]
    fn channels_cover_all_bands() {
        assert_eq!(channel_of(2412), 1);
        assert_eq!(channel_of(2484), 14);
        assert_eq!(channel_of(5825), 165);
        assert_eq!(channel_of(6115), 33);
        assert_eq!(channel_of(100), 0);
    }

    #[test]
    fn analysis_reports_density_and_movement() {
        let aps = parse_iw_scan(SAMPLE);
        let first = analyze(aps.clone(), None);
        assert_eq!((first.ap_count, first.density, first.environment), (3, "sparse", "unknown"));
        assert_eq!(first.channels[&6], 1);

        let same = analyze(aps.clone(), Some(&first.access_points));
        assert_eq!((same.similarity, same.environment), (Some(1.0), "stationary"));

        let moved = analyze(Vec::new(), Some(&aps));
        assert_eq!((moved.similarity, moved.environment), (Some(0.0), "moved"));
        assert_eq!((moved.density, moved.mean_rssi_dbm), ("none", None));
    }

    #[test]
    fn parses_nmcli_output_with_escaped_colons() {
        let text = "AA\\:BB\\:CC\\:00\\:11\\:22:home\\:net:2437 MHz:80\n\
                    AA\\:BB\\:CC\\:33\\:44\\:55::5180 MHz:40\n\
                    not a scan line\n";
        let aps = parse_nmcli(text);
        assert_eq!(aps.len(), 2);
        assert_eq!((aps[0].ssid.as_str(), aps[0].channel, aps[0].rssi_dbm), ("home:net", 6, -60.0));
        assert_eq!(aps[0].bssid, "aa:bb:cc:00:11:22");
        assert_eq!((aps[1].ssid.as_str(), aps[1].channel, aps[1].rssi_dbm), ("", 36, -80.0));
    }

    #[test]
    fn bssid_is_not_serialized() {
        let json = serde_json::to_string(&parse_iw_scan(SAMPLE)[0]).unwrap();
        assert!(!json.contains("aa:bb:cc"));
    }
}
