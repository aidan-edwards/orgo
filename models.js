// Turns OpenRouter's /api/v1/models JSON into a short candidate list for the orgo planner.
// Runs with macOS's built-in JavaScript (osascript -l JavaScript models.js <file>).
ObjC.import('Foundation');
function run(argv) {
  var txt = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  var data = (JSON.parse(txt).data) || [];
  var rows = [];
  data.forEach(function (m) {
    var id = m.id || '';
    var p = m.pricing || {};
    var inP = parseFloat(p.prompt) * 1e6, outP = parseFloat(p.completion) * 1e6;
    var params = m.supported_parameters || [];
    if (/^(anthropic|openrouter)\//.test(id)) return;   // no Claude, no meta-routers
    if (/:free$/.test(id)) return;                        // free tiers are rate limited
    if (params.indexOf('tools') < 0) return;              // Claude Code needs tool use
    if ((m.context_length || 0) < 128000) return;         // coding needs room
    if (!(inP > 0) || !(outP > 0)) return;
    rows.push({ id: id, inP: inP, outP: outP, ctx: m.context_length });
  });
  rows.sort(function (a, b) { return a.outP - b.outP; });
  return rows.slice(0, 200).map(function (r) {
    return r.id + ' | ' + r.inP.toFixed(3) + ' | ' + r.outP.toFixed(3) + ' | ' + Math.round(r.ctx / 1000) + 'K';
  }).join('\n');
}
