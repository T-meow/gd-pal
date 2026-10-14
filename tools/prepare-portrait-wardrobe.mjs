import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const packRoot = path.join(root, 'assets/characters/blue_whale');
const manifestPath = path.join(packRoot, 'manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const visual = manifest.visuals.portrait2d;

// Read alpha bounds without changing generated pixels. Ignore nearly invisible fringe.
function metadata(file, view) {
  const png = fs.readFileSync(file), width = png.readUInt32BE(16), height = png.readUInt32BE(20);
  if (png[24] !== 8 || png[25] !== 6 || png[28] !== 0) throw Error('Expected non-interlaced 8-bit RGBA PNG: ' + file);
  const chunks = [];
  for (let offset = 8; offset < png.length;) {
    const size = png.readUInt32BE(offset), type = png.toString('ascii', offset + 4, offset + 8);
    if (type === 'IDAT') chunks.push(png.subarray(offset + 8, offset + 8 + size));
    offset += size + 12;
  }
  const raw = zlib.inflateSync(Buffer.concat(chunks)), stride = width * 4;
  let previous = Buffer.alloc(stride), offset = 0, left = width, top = height, right = -1, bottom = -1;
  for (let y = 0; y < height; y++) {
    const filter = raw[offset++], row = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= 4 ? row[x - 4] : 0, b = previous[x], c = x >= 4 ? previous[x - 4] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      const prediction = filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? Math.floor((a + b) / 2) : pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      row[x] = (raw[offset++] + prediction) & 255;
    }
    for (let x = 0; x < width; x++) if (row[x * 4 + 3] > 200) {
      left = Math.min(left, x); top = Math.min(top, y); right = Math.max(right, x); bottom = Math.max(bottom, y);
    }
    previous = row;
  }
  if (right < left) throw Error('No visible character in ' + file);
  return { canvas_size: [width, height], alpha_bounds: [left, top, right - left + 1, bottom - top + 1], anchor: [0.5, view === 'call' ? 1 : (bottom + 1) / height] };
}

function addPose(id, source, outfit, view, label, landscape = false) {
  const file = `images/outfits/${outfit}/${path.basename(source)}`, destination = path.join(packRoot, file);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  if (!fs.existsSync(destination)) fs.copyFileSync(source, destination);
  visual.poses[id] = { file, label, view, outfit, landscape, tags: [outfit], ...metadata(destination, view) };
}

for (const [id, pose] of Object.entries(visual.poses)) pose.outfit = id.includes('nightdress') ? 'nightdress' : 'maid';
for (const emotion of ['happy', 'shy']) addPose(`full_nightdress_${emotion}`, path.join(root, `output/imagegen/whale-maid-nightdress-v2/images/full_body/full_nightdress_${emotion}.png`), 'nightdress', 'full_body', `睡衣·${emotion === 'happy' ? '开心' : '害羞'}`);
visual.outfits = {
  maid: { label: '女仆装', defaults: { full_body: 'full_idle', call: 'call_listen' } },
  nightdress: { label: '睡衣', defaults: { full_body: 'full_nightdress_happy', call: 'call_nightdress_happy' } }
};
visual.default_outfit = 'maid';
delete visual.actions.nightdress_happy;
delete visual.actions.nightdress_shy;
function mapOutfit(entry, outfit, view, pose) {
  entry.outfits ??= {}; entry.outfits[outfit] ??= {}; entry.outfits[outfit][view] = pose;
}
for (const action of ['idle', 'listen', 'respond', 'happy', 'shy', 'drag']) {
  const emotion = action === 'shy' ? 'shy' : 'happy';
  for (const view of ['full_body', 'call']) mapOutfit(visual.actions[action], 'nightdress', view, `${view === 'full_body' ? 'full' : 'call'}_nightdress_${emotion}`);
}
for (const expression of ['neutral', 'happy', 'shy']) for (const view of ['full_body', 'call']) {
  mapOutfit(visual.expressions[expression], 'nightdress', view, `${view === 'full_body' ? 'full' : 'call'}_nightdress_${expression === 'shy' ? 'shy' : 'happy'}`);
}
for (const [folder, outfit, view] of [
  ['whale-maid-expressions-fullbody-v1', 'maid', 'full_body'],
  ['whale-maid-expressions-closeup-v1', 'maid', 'call'],
  ['whale-maid-nightdress-expressions-closeup-v1', 'nightdress', 'call']
]) {
  const base = path.join(root, 'output/imagegen', folder), generated = JSON.parse(fs.readFileSync(path.join(base, 'generation.json'), 'utf8'));
  for (const asset of generated.assets) {
    const emotion = asset.id.replace(/^(full|call)_(nightdress_)?/, '');
    addPose(asset.id, path.join(base, asset.file), outfit, view, asset.label);
    visual.actions[emotion] ??= { label: asset.label, category: '表情', mode: 'once', seconds: 4, preserve_activity: false, views: {} };
    visual.expressions[emotion] ??= { label: asset.label, views: {} };
    for (const entry of [visual.actions[emotion], visual.expressions[emotion]]) {
      if (outfit === 'maid') entry.views[view] = asset.id;
      else mapOutfit(entry, outfit, view, asset.id);
    }
  }
}
const restRoot = path.join(root, 'output/imagegen/whale-maid-desktop-rest-v1');
const rest = JSON.parse(fs.readFileSync(path.join(restRoot, 'generation.json'), 'utf8'));
if (rest.completed_count !== 4) throw Error('Rest images are not complete');
for (const asset of rest.assets) addPose(asset.id, path.join(restRoot, asset.file), asset.outfit, 'full_body', asset.label, true);
for (const [id, label, pose] of [['sit', '坐下', 'sit'], ['prone', '趴下', 'prone'], ['sit_edge', '坐在边缘', 'sit'], ['edge_rest', '趴在边缘', 'prone']]) {
  visual.actions[id] = { label, category: '桌宠', mode: 'hold', seconds: 0, preserve_activity: true, internal: id === 'edge_rest', views: { full_body: `full_${pose}` }, outfits: { nightdress: { full_body: `full_nightdress_${pose}` } } };
}
const fullSleepRoot = path.join(root, 'output/imagegen/whale-maid-nightdress-fullbody-complete-v1');
const fullSleepRecord = path.join(fullSleepRoot, 'generation.json');
if (fs.existsSync(fullSleepRecord)) {
  const fullSleep = JSON.parse(fs.readFileSync(fullSleepRecord, 'utf8'));
  for (const asset of fullSleep.assets) {
    addPose(asset.id, path.join(fullSleepRoot, asset.file), 'nightdress', 'full_body', asset.label);
    for (const group of [visual.actions, visual.expressions]) for (const entry of Object.values(group)) {
      if (entry.views?.full_body === asset.maid_pose) mapOutfit(entry, 'nightdress', 'full_body', asset.id);
    }
    if (asset.maid_pose === 'full_idle') visual.outfits.nightdress.defaults.full_body = asset.id;
  }
}
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ poses: Object.keys(visual.poses).length, outfits: Object.keys(visual.outfits), rest_images: rest.assets.length }));
