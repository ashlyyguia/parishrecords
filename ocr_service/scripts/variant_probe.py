"""Tries pipeline variants (scale / contrast) on refused photos. Structure only."""
import sys, pathlib, json
import cv2, numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from app.errors import OcrError
from app.pipeline.column_template import BAPTISMAL_REGISTER, MARRIAGE_REGISTER
from app.pipeline.inversion import correct_spread_inversion
from app.pipeline.orientation import correct_orientation
from app.pipeline.rectify import rectify_page
from app.pipeline.spread import split_spread
from app.pipeline.table import detect_spread_grids

def pipeline(img, template):
    o = correct_orientation(img)
    s = correct_spread_inversion(o.image).image
    p = split_spread(s)
    l = rectify_page(p.left).image; r = rectify_page(p.right).image
    return detect_spread_grids(l, r, spread_template=template)

def clahe(img):
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)

VARIANTS = {
  'orig': lambda i: i,
  's0.75': lambda i: cv2.resize(i, None, fx=0.75, fy=0.75, interpolation=cv2.INTER_AREA),
  's0.5': lambda i: cv2.resize(i, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA),
  's1.25': lambda i: cv2.resize(i, None, fx=1.25, fy=1.25, interpolation=cv2.INTER_CUBIC),
  'clahe': clahe,
  'clahe0.75': lambda i: clahe(cv2.resize(i, None, fx=0.75, fy=0.75, interpolation=cv2.INTER_AREA)),
}
template = {'baptismal': BAPTISMAL_REGISTER, 'marriage': MARRIAGE_REGISTER}[sys.argv[1]]
for p in sys.argv[2:]:
    img = cv2.imdecode(np.fromfile(p, np.uint8), cv2.IMREAD_COLOR)
    out = {'file': pathlib.Path(p).name}
    for name, fn in VARIANTS.items():
        try:
            g = pipeline(fn(img), template)
            out[name] = 'OK %d/%d' % (len({c.row for c in g.left.cells}), len({c.row for c in g.right.cells}))
        except OcrError as e:
            out[name] = '%s:%s' % (e.reason, e.side)
        except Exception as e:
            out[name] = 'EXC ' + type(e).__name__
    print(json.dumps(out), flush=True)
