import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const destination = path.resolve(process.argv[2] ?? '');
const exportsRoot = path.join(project, 'exports') + path.sep;
if (!process.argv[2] || !destination.startsWith(exportsRoot)) {
  throw new Error('Pass a staging directory inside the project exports directory.');
}
const starter = path.join(destination, 'starter');
const personaDirectory = path.join(destination, 'persona');
fs.mkdirSync(personaDirectory, { recursive: true });
const profile = fs.readFileSync(path.join(project, 'scripts/characters/pal_profile.gd'), 'utf8');
const persona = profile.match(/const DEFAULT_PERSONA := """([\s\S]*?)"""/)?.[1];
const displayName = profile.match(/const DEFAULT_NAME := "([^"]+)"/)?.[1];
if (!persona || !displayName) throw new Error('The default persona or name is missing.');
const json = value => JSON.stringify(value, null, 2) + '\n';
const documents = {
  'persona.json': json({ schema_version: 1, display_name: displayName, persona }),
  'persona.md': '# ' + displayName + '\n\n' + persona + '\n',
};
const manifest = {
  schema_version: 1, package_type: 'persona', profile_id: 'blue_whale_starter',
  display_name: displayName, session_count: 0, message_count: 0,
  files: Object.entries(documents).map(([name, text]) => ({
    path: name, bytes: Buffer.byteLength(text),
    sha256: crypto.createHash('sha256').update(text).digest('hex').toUpperCase(),
  })),
};
documents['manifest.json'] = json(manifest);
for (const [name, text] of Object.entries(documents)) {
  fs.writeFileSync(path.join(personaDirectory, name), text);
}

const assetPath = 'assets/characters/blue_whale';
const source = path.join(project, assetPath);
const assetManifest = JSON.parse(fs.readFileSync(path.join(source, 'manifest.json'), 'utf8'));
const visual = assetManifest.visuals[assetManifest.default_visual];
const images = new Set(Object.values(visual.poses).map(pose => pose.file));
if (assetManifest.preview) images.add(assetManifest.preview);
const copy = (from, to) => {
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
};
for (const image of images) {
  if (typeof image !== 'string' || !/^images\/(?:[^/\\:]+\/)*[^/\\:]+\.(png|webp)$/i.test(image) || image.split('/').includes('..')) {
    throw new Error('Invalid portrait path: ' + image);
  }
  copy(path.join(source, image), path.join(starter, assetPath, image));
}
for (const name of ['manifest.json', 'README.md']) {
  copy(path.join(source, name), path.join(starter, assetPath, name));
}
copy(path.join(project, 'LICENSE'), path.join(starter, 'LICENSE'));
fs.writeFileSync(path.join(starter, 'README.md'), `# 肥鱼初始包\n\n包含 ${images.size} 张立绘和普通人设，格式为 v1。\n\n- 使用程序：在「伙伴档案 → 导入导出」选择本目录的 persona.zip，预览后导入。\n- 使用源码：将本目录的 assets/ 合并到源码根目录，再用 Godot 导入。\n- Windows 和 Android 发布程序已带齐立绘，无需复制图片。\n\n本包不含个人聊天、记忆、世界设定、连接凭据或 Agent 配置。\n图片生成来源见 assets/characters/blue_whale/README.md，项目许可证见 LICENSE。\n`);
console.log(`Staged ${images.size} portraits and a clean v1 persona in ${destination}`);
