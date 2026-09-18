/**
 * Reconcile the OCR word frame with the CV grid frame.
 *
 * The CV service returns each rectified page image together with its grid cells
 * in that image's own pixel frame. But OCR does not run on that image directly:
 * the route first passes it through `preprocessForOcr` with an OCR.space-friendly
 * `maxEdge`, which DOWNSCALES any page larger than that bound (marriage pages are
 * ~3048px tall, over the 2500 cap). OCR.space then returns word boxes in the
 * downscaled frame, while `gridToRows` / `marriageGridToRows` test those boxes
 * against cells in the original, larger frame -- so without this step every word
 * lands in the wrong cell (columns collapse, groom/bride swap).
 *
 * This scales word vertices from the frame OCR actually saw (`preppedDims`) back
 * up into the grid's frame (`gridPage.width`/`.height`). When no downscale
 * happened -- the page was already within `maxEdge`, or `preprocessForOcr` fell
 * back to the original buffer because sharp was unavailable -- the two frames
 * match (or `preppedDims` is null) and the words are returned unchanged.
 */
function rescaleWordsToGrid(words, gridPage, preppedDims) {
  if (
    !preppedDims ||
    !preppedDims.width ||
    !preppedDims.height ||
    !gridPage ||
    !gridPage.width ||
    !gridPage.height
  ) {
    return words;
  }
  const sx = gridPage.width / preppedDims.width;
  const sy = gridPage.height / preppedDims.height;
  if (Math.abs(sx - 1) < 1e-9 && Math.abs(sy - 1) < 1e-9) return words;
  return (words || []).map((w) => ({
    ...w,
    vertices: w.vertices.map((v) => ({ x: v.x * sx, y: v.y * sy })),
  }));
}

module.exports = { rescaleWordsToGrid };
