# Analytics tab — copy pass (Yahia's rule: no raw text, no ugly long text)

Continue on your branch (f9b9ee8). Same rules: no merge, no push, no package.sh, sandbox copies only, gates in the foreground.

Yahia reviewed the stills and said: QC reason must read "Blurry footage", and "no raw text or ugly long text we dont need to see". Apply that to the whole Analytics tab:

1. QC reasons: map engine codes to short human labels in ONE place (e.g. soft:sharpness -> "Blurry footage", loudness -> "Bad audio level", captions overflow -> "Captions too long"; check the real codes in events/qc code). Unknown code -> "Other", never the raw code. Prefer showing it as a small caption under the FAILED QC tile ("Mostly blurry footage") over a separate sentence line.
2. Empty state: replace the long sentence with one short line, e.g. "Charts start after your first post."
3. Sweep every Analytics sub-tab (Overview, What works, Audience & platforms, Money, Pipeline health, Suggestions) in BOTH real-sandbox and fixture mode: no snake_case, ids (cmp_/mom_/edit ids), stage keys, error strings, raw timestamps, or multi-sentence explanations. Short plain labels; empty sub-tabs get one short line each.
4. The header status pill showed "Held back designedbymalik 0:..." (truncated raw text). If it is formatted in the Swift shell, make it a short plain phrase (e.g. "1 clip held back"); if it needs an engine change, leave it and say so.
5. Re-shoot: real sandbox dark+light 1440x900 for Overview + each sub-tab, fixture dark 1440x900 Overview. Look at every still yourself and list any text you were unsure about.

Done = swift build + swift test + engine pytest green (paste counts), stills re-shot, README updated, commit.
