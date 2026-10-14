import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(project, 'output/imagegen/whale-maid-builtin-complete-v1');
const target = join(project, 'assets/characters/blue_whale');
const portable = join(project, 'output/character-packs/blue-whale-v1');
const manifest = JSON.parse(readFileSync(join(source, 'manifest.json'), 'utf8'));
manifest.pack_id = 'blue_whale';
manifest.name = '蓝色肥鱼';
delete manifest.reference;
const visual = manifest.visuals.portrait2d;
const extraSources = new Map();

// Read the real PNG canvas and alpha bounds without changing the source image.
function pngMetadata(file, view) {
  const png = readFileSync(file);
  const width = png.readUInt32BE(16);
  const height = png.readUInt32BE(20);
  const bytesPerSample = png[24] / 8;
  const colorType = png[25];
  if (png.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || ![1, 2].includes(bytesPerSample) || ![2, 6].includes(colorType) || png[28] !== 0) {
    throw new Error(`Expected a non-interlaced 8/16-bit RGB/RGBA PNG: ${file}`);
  }
  let bounds = [0, 0, width, height];
  if (colorType === 6) {
    const chunks = [];
    for (let offset = 8; offset < png.length;) {
      const length = png.readUInt32BE(offset);
      if (png.toString('ascii', offset + 4, offset + 8) === 'IDAT') chunks.push(png.subarray(offset + 8, offset + 8 + length));
      offset += length + 12;
    }
    const pixels = inflateSync(Buffer.concat(chunks));
    const bytesPerPixel = 4 * bytesPerSample;
    const stride = width * bytesPerPixel;
    let previous = Buffer.alloc(stride);
    let left = width, top = height, right = -1, bottom = -1;
    for (let y = 0; y < height; y++) {
      const offset = y * (stride + 1);
      const filter = pixels[offset];
      if (filter > 4) throw new Error(`Unsupported PNG filter: ${file}`);
      const row = Buffer.allocUnsafe(stride);
      for (let x = 0; x < stride; x++) {
        const a = x >= bytesPerPixel ? row[x - bytesPerPixel] : 0;
        const b = previous[x];
        const c = x >= bytesPerPixel ? previous[x - bytesPerPixel] : 0;
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        const predictor = filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? Math.floor((a + b) / 2) : (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
        row[x] = (pixels[offset + 1 + x] + predictor) & 255;
      }
      for (let x = 0; x < width; x++) {
        const alphaOffset = x * bytesPerPixel + 3 * bytesPerSample;
        const alpha = bytesPerSample === 2 ? row.readUInt16BE(alphaOffset) : row[alphaOffset];
        if (alpha === 0) continue;
        left = Math.min(left, x); right = Math.max(right, x);
        top = Math.min(top, y); bottom = Math.max(bottom, y);
      }
      previous = row;
    }
    if (right < 0) throw new Error(`Empty portrait: ${file}`);
    bounds = [left, top, right - left + 1, bottom - top + 1];
  }
  return { canvas_size: [width, height], anchor: [0.5, view === 'full_body' ? (bounds[1] + bounds[3]) / height : 1], alpha_bounds: bounds };
}

function addPortrait(id, view, label, tags, sourcePath) {
  const file = `images/${view}/${id}.png`;
  const absoluteSource = join(project, 'output/imagegen', sourcePath);
  visual.poses[id] = { file, label, view, tags, ...pngMetadata(absoluteSource, view) };
  extraSources.set(file, absoluteSource);
}

for (const [expression, label] of [['happy', '开心'], ['shy', '害羞']]) {
  for (const [view, prefix, version] of [['full_body', 'full', 'v2'], ['call', 'call', 'v1']]) {
    const id = `${prefix}_nightdress_${expression}`;
    addPortrait(id, view, `${view === 'full_body' ? '全身' : '近景'}·睡裙${label}`, ['nightdress', expression], `whale-maid-nightdress-${version}/images/${view}/${id}.png`);
  }
  visual.actions[`nightdress_${expression}`] = {
    label: `睡裙·${label}`, category: '睡裙', mode: 'hold', preserve_activity: true,
    views: { full_body: `full_nightdress_${expression}`, call: `call_nightdress_${expression}` },
  };
}
for (const [id, label, sourcePath] of [
  ['tease_popsicle', '舔蓝色冰棍', 'whale-maid-intimacy-nano-v1/closeup_blush_blue_popsicle.png'],
  ['tease_tongue_ok', '吐舌比 OK', 'whale-maid-intimacy-nano-v2/closeup_tongue_ok_matching_popsicle_expression.png'],
]) {
  addPortrait(`call_${id}`, 'call', `近景·${label}`, ['intimacy', id], sourcePath);
  visual.actions[id] = { label, category: '亲密互动', mode: 'once', seconds: 6, preserve_activity: true, views: { call: `call_${id}` } };
}
const counts = {};
for (const pose of Object.values(visual.poses)) counts[pose.view] = (counts[pose.view] ?? 0) + 1;
manifest.description = `鲸鱼娘 AI 女仆，${counts.full_body} 张全身立绘与 ${counts.call} 张通话近景。`;
const actions = visual.actions;
actions.thinking = actions.think;
delete actions.think;
actions.thinking.mode = 'once';
actions.thinking.seconds = 4;
for (const [id, expression] of Object.entries(visual.expressions)) {
  if (['neutral', 'thinking', 'affectionate'].includes(id)) continue;
  actions[id] ??= { mode: 'once', seconds: id === 'shy' ? 5 : 4, views: expression.views };
}
actions.head_pat = actions.headpat;
delete actions.headpat;
actions.drag = { mode: 'hold', internal: true, views: { ...actions.pickup.views, call: 'call_surprised' } };
actions.walk = { mode: 'hold', internal: true, views: { ...actions.walk_right.views } };
// This is a separate closed-eye portrait, not an aligned animation frame.
actions.blink.seconds = 2;
delete actions.blink.internal;
const labels = {
  idle: '安静待机', greet: '挥手招呼', listen: '认真倾听', respond: '温柔回应', thinking: '认真思考',
  drink_water: '喝水', eat_snack: '吃零食', read: '阅读', work: '记录与工作', comfort: '安慰陪伴',
  cheer: '鼓励加油', yawn: '打哈欠', sleep: '闭眼小睡', stretch: '伸懒腰', blink: '闭眼片刻',
  happy: '开心', laugh: '开怀大笑', shy: '害羞脸红', surprised: '惊讶', sad: '低落', worried: '担心',
  annoyed: '轻微不满', sleepy: '困倦', apologize: '认真道歉', proud: '小小得意', head_pat: '摸摸头',
  pickup: '被提起', sit_edge: '坐在窗口边缘', walk_left: '向左慢走', walk_right: '向右慢走',
  drag: '拖动反应', walk: '慢走',
};
const daily = new Set(['drink_water', 'eat_snack', 'read', 'work', 'yawn', 'sleepy', 'sleep', 'stretch', 'blink']);
const desktop = new Set(['pickup', 'sit_edge', 'walk_left', 'walk_right', 'drag', 'walk']);
const preserveActivity = new Set([
  'drink_water', 'eat_snack', 'read', 'work', 'sleep', 'stretch', 'head_pat', 'blink', ...desktop,
]);
for (const [id, action] of Object.entries(actions)) {
  action.label ??= labels[id] ?? id;
  action.category ??= daily.has(id) ? '日常' : (desktop.has(id) ? '桌宠' : (id in visual.expressions ? '表情' : '交流'));
  action.preserve_activity ??= preserveActivity.has(id);
  action.seconds ??= action.mode === 'segment' ? 2.5 : 0;
}
for (const [id, expression] of Object.entries(visual.expressions)) expression.label = labels[id] ?? ({neutral:'平静',affectionate:'温柔亲近'}[id] ?? id);
visual.capabilities = { can_wander: false, look_at_mouse: false };
const readme = `# 蓝色肥鱼

内置静态 2D 角色包 v1。${Object.keys(visual.poses).length} 张 PNG，${counts.full_body} 张全身、${counts.call} 张通话近景。包含原版鲸鱼娘女仆造型和睡裙造型。manifest.json 定义实际画布、锚点、动作与表情映射。

全身与通话只提供当前视图实际有图的动作。摸头使用独立回应图，桌宠拖动使用被提起图；阅读、记录、安慰、小睡和伸展均覆盖两个视图。坐窗边与左右慢走为静态姿势；通话闭眼为独立立绘，展示两秒。

“睡裙”分组提供开心、害羞，可持续保持；全身采用 whale-maid-nightdress-v2 修正版，近景采用 whale-maid-nightdress-v1。“亲密互动”提供舔蓝色冰棍和吐舌比 OK，仅近景可用，各展示六秒；吐舌采用 whale-maid-intimacy-nano-v2 最新版。亲密近景保留生成图的浅蓝底色，其余立绘为透明 PNG。

基础图和睡裙图使用 Codex 内置 image_gen 生成，亲密近景使用 mxai Nano 2.0 生成。源图和提示词保留在 output/imagegen 下对应目录。直接查看 images/full_body/ 与 images/call/ 中的图片。
`;
for (const destination of [target, portable]) {
  for (const pose of Object.values(visual.poses)) {
    const dest = join(destination, pose.file);
    mkdirSync(dirname(dest), {recursive:true});
    copyFileSync(extraSources.get(pose.file) ?? join(source, pose.file), dest);
  }
  writeFileSync(join(destination, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(join(destination, 'README.md'), readme);
}
console.log(JSON.stringify({target,portable,poses:Object.keys(visual.poses).length,actions:Object.keys(actions).length}));
