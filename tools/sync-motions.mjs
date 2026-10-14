import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Copy only Godot body animations and their provenance; no duplicate VRM meshes.
const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve('D:/GameAssetLibrary/02_Animations/Humanoid/MMD');
const destination = path.join(project, 'assets/motions/npc');
const sourceManifest = JSON.parse(fs.readFileSync(path.join(source, 'exports/manifest.json'), 'utf8'));
const selection = JSON.parse(fs.readFileSync(path.join(project, 'tools/motion-selection.json'), 'utf8'));
const installedPath = path.join(destination, 'manifest.json');
const installed = fs.existsSync(installedPath) ? JSON.parse(fs.readFileSync(installedPath, 'utf8')) : null;
const sourceClips = new Map(sourceManifest.clips.map(clip => [clip.id, clip]));
const installedClips = new Map(installed?.clips.map(clip => [clip.id, clip]) ?? []);
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
if (!process.argv[3]) throw new Error('Pass the original motion-library reference VRM as the second argument. It is checked locally, never copied into the project.');
const avatarHash = sha256(fs.readFileSync(path.resolve(process.argv[3])));
const installedCatalog = path.join(destination, 'catalog.gd');
if (fs.existsSync(installedCatalog)) {
  const installedHash = fs.readFileSync(installedCatalog, 'utf8').match(/const AVATAR_SHA256 := "([a-f0-9]{64})"/)?.[1];
  if (installedHash !== avatarHash) throw new Error('Source avatar differs from the installed motion library');
}
// Keep previously accepted animations byte-for-byte, and refresh only the selected additions.
const plans = selection.preserveExisting.map(id => ({
  clip: installedClips.get(id) ?? sourceClips.get(id),
  local: installedClips.has(id),
  id,
}));
for (const entry of selection.clips) {
  const original = sourceClips.get(entry.id);
  if (!original) throw new Error(`Selected motion is missing from source: ${entry.id}`);
  const { id, label, category, categoryLabel, expressions } = entry;
  plans.push({ id, local: false, clip: {
    ...original,
    label: label ?? original.label,
    category: category ?? original.category,
    categoryLabel: categoryLabel ?? original.categoryLabel,
    expressions: { ...original.expressions, ...expressions },
    sourceMetadata: {
      generatedAt: sourceManifest.generatedAt,
      label: original.label, category: original.category, categoryLabel: original.categoryLabel,
      expressions: original.expressions,
    },
  } });
}
const ids = new Set();
const copies = new Map();
for (const { clip, local, id } of plans) {
  if (!clip) throw new Error(`Preserved motion is missing: ${id}`);
  if (!/^[a-z0-9_]+$/.test(clip.id) || ids.has(clip.id)) throw new Error(`Invalid/duplicate ID: ${clip.id}`);
  ids.add(clip.id);
  if (!['loop', 'once', 'hold'].includes(clip.mode)) throw new Error(`Invalid mode: ${clip.id}`);
  const relative = clip.files.godot;
  if (!/^\d{2}_[a-z]+\/(?:[a-z0-9_]+\/)*[a-z0-9_]+\.tres$/.test(relative)) throw new Error(`Invalid resource path: ${relative}`);
  const data = fs.readFileSync(path.join(local ? destination : path.join(source, 'exports'), relative));
  if (sha256(data) !== clip.sha256.godot) throw new Error(`Animation hash mismatch: ${clip.id}`);
  if (!local) copies.set(relative, data);
  for (const evidence of clip.license.copiedEvidence ?? []) {
    if (!/^licenses\/source-documents\/[a-z0-9]+\.txt$/.test(evidence)) throw new Error(`Invalid evidence path: ${evidence}`);
    const evidenceData = fs.readFileSync(path.join(local ? destination : source, evidence));
    if (!local) copies.set(evidence, evidenceData);
  }
}
const clips = plans.map(plan => plan.clip);
const countBy = key => clips.reduce((counts, clip) => {
  counts[clip[key]] = (counts[clip[key]] ?? 0) + 1;
  return counts;
}, {});
const maximum = (format, key) => Math.max(0, ...clips.map(clip => clip.validation?.[format]?.[key] ?? 0));
const manifest = {
  generatedAt: new Date().toISOString(),
  target: 'DS (adapted humanoid motions)',
  totals: { clips: clips.length, categories: countBy('categoryLabel'), modes: countBy('mode') },
  fps: sourceManifest.fps,
  maxGlbJointErrorMetres: maximum('glb', 'maxJointPositionErrorMetres'),
  maxGodotJointErrorMetres: maximum('godot', 'max_playback_position_error_metres'),
  maxGodotRotationErrorRadians: maximum('godot', 'max_playback_rotation_error_radians'),
  legacyIds: sourceManifest.legacyIds,
  selection: 'tools/motion-selection.json',
  sourceGeneratedAt: sourceManifest.generatedAt,
  sourceTotals: sourceManifest.totals,
  clips,
};
const sourceLicense = fs.readFileSync(path.join(source, 'licenses/source.json'));
// Validate the complete source set before writing any project files.
for (const [relative, data] of copies) {
  const target = path.join(destination, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, data);
}
fs.writeFileSync(path.join(destination, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
fs.writeFileSync(path.join(destination, 'licenses/source.json'), sourceLicense);
const compact = clips.map(clip => ({
  id: clip.id, label: clip.label, category: clip.category, category_label: clip.categoryLabel,
  mode: clip.mode, seconds: clip.seconds, expressions: clip.expressions, support: clip.support,
}));
// A script constant is included by Godot's resource dependency scanner in builds.
fs.writeFileSync(path.join(destination, 'catalog.gd'),
  '# Generated by tools/sync-motions.mjs; selection and labels: tools/motion-selection.json.\n' +
  'extends RefCounted\n\nconst AVATAR_SHA256 := ' + JSON.stringify(avatarHash) + '\n' +
  'const CLIPS := ' + JSON.stringify(compact, null, '\t') + '\n');
const resourceLines = clips.map((clip, i) =>
  `[ext_resource type="Animation" path="res://assets/motions/npc/${clip.files.godot}" id="${i + 1}"]`);
const entries = clips.map((clip, i) => `${JSON.stringify(clip.id)}: ExtResource("${i + 1}")`);
fs.writeFileSync(path.join(destination, 'npc_motions.tres'),
  `[gd_resource type="AnimationLibrary" load_steps=${clips.length + 1} format=3]\n\n` +
  resourceLines.join('\n') + '\n\n[resource]\n_data = {\n' + entries.join(',\n') + '\n}\n');
console.log(`Synced ${clips.length} Godot motions, catalog and license evidence to ${destination}`);
