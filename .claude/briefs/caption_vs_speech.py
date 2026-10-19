# Timeline: what he says (keep-mapped to output time) vs what is on screen (depth cards + front boxes).
import json, sys
d = json.load(open(sys.argv[1])); m = json.load(open(sys.argv[1].replace('.json', '.mp4.meta.json')))
keep = d['keep']
def out_t(t):
    acc = 0.0
    for a, b in keep:
        if a <= t <= b: return acc + (t - a)
        acc += b - a
    return None
words = [(out_t(w['start']), w['word']) for w in d['words'] if out_t(w['start']) is not None]
spoken = set(w.lower().strip('.,!?;:"\'') for _, w in words)
ev = [(c['t0'], c['t1'], 'CARD ' + c['status'], (' '.join(c.get('lead') or []) + ' / ' + (c.get('carry') or '')).strip(' /') or c['text']) for c in m['depth']['cards'] if c['status'] in ('depth', 'fallback_front')]
ev += [(b['t0'], b['t1'], 'box y%d' % b['box'][1], b['text']) for b in m['boxes']]
ev.sort()
until = float(sys.argv[2]) if len(sys.argv) > 2 else 99
for t0, t1, kind, text in ev:
    if t0 > until: break
    said = ' '.join(w for t, w in words if t0 - 1.0 <= t < t1)
    first = next((t for t, w in words if w.lower().strip('.,!?;:"\'$') in [x.lower().strip('.,!?;:"\'$') for x in text.split()]), None)
    invented = [x for x in text.replace('/', ' ').split() if x.lower().strip('.,!?;:"\'') not in spoken]
    print(f"{t0:6.2f}-{t1:5.2f} {kind:20s} {text[:34]:34s} | said[-1s..end]: {said[:70]}" + (f"  !!NOT SPOKEN: {invented}" if invented else ''))
