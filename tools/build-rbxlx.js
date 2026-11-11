// Régénère MiniMotorwaysRBX.rbxlx à partir de src/ sans Rojo.
//
// Équivalent de tools/build.ps1 (rojo build + fix-source-tags.js) pour les
// machines où Rojo n'est pas installé. Les services statiques (Lighting,
// Players, SoundService, Workspace) sont conservés tels quels depuis le
// fichier existant ; seuls ReplicatedStorage, ServerScriptService et
// StarterPlayer sont reconstruits depuis default.project.json et src/.
//
// usage : node tools/build-rbxlx.js [sortie.rbxlx]
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const outPath = path.resolve(root, process.argv[2] || "MiniMotorwaysRBX.rbxlx");
const project = JSON.parse(fs.readFileSync(path.join(root, "default.project.json"), "utf8"));
const previous = fs.readFileSync(outPath, "utf8");

// Bloc <Item class="X" ...> ... </Item> de premier niveau (indentation 2).
function topLevelBlock(xml, className) {
	const start = xml.indexOf(`\n  <Item class="${className}" `);
	if (start < 0) throw new Error(`Bloc ${className} introuvable dans ${outPath}`);
	const end = xml.indexOf("\n  </Item>", start);
	return xml.slice(start + 1, end + "\n  </Item>".length) + "\n";
}

let referent = 0;
const escapeXml = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const cdata = (s) => "<![CDATA[" + s.replace(/\]\]>/g, "]]]]><![CDATA[>") + "]]>";

function scriptItem(file, depth) {
	const base = path.basename(file, ".luau");
	let className = "ModuleScript";
	let name = base;
	if (base.endsWith(".server")) {
		className = "Script";
		name = base.slice(0, -".server".length);
	} else if (base.endsWith(".client")) {
		className = "LocalScript";
		name = base.slice(0, -".client".length);
	}
	const pad = "  ".repeat(depth);
	const source = fs.readFileSync(file, "utf8");
	let xml = `${pad}<Item class="${className}" referent="${referent++}">\n`;
	xml += `${pad}  <Properties>\n`;
	xml += `${pad}    <string name="Name">${escapeXml(name)}</string>\n`;
	if (className === "Script") xml += `${pad}    <token name="RunContext">0</token>\n`;
	xml += `${pad}    <ProtectedString name="Source">${cdata(source)}</ProtectedString>\n`;
	xml += `${pad}  </Properties>\n`;
	xml += `${pad}</Item>\n`;
	return xml;
}

function folderItem(name, dir, depth, className) {
	const pad = "  ".repeat(depth);
	let xml = `${pad}<Item class="${className || "Folder"}" referent="${referent++}">\n`;
	xml += `${pad}  <Properties>\n${pad}    <string name="Name">${escapeXml(name)}</string>\n${pad}  </Properties>\n`;
	xml += dirChildren(dir, depth + 1);
	xml += `${pad}</Item>\n`;
	return xml;
}

function dirChildren(dir, depth) {
	const entries = fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !e.name.startsWith("."));
	const items = entries
		.filter((e) => e.isDirectory() || e.name.endsWith(".luau"))
		.map((e) => ({ e, key: e.isDirectory() ? e.name : e.name.replace(/\.(server|client)?\.?luau$/, "") }))
		.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
	let xml = "";
	for (const { e } of items) {
		const full = path.join(dir, e.name);
		xml += e.isDirectory() ? folderItem(e.name, full, depth) : scriptItem(full, depth);
	}
	return xml;
}

// Construit un service (ou conteneur) depuis un nœud du project.json.
function node(name, spec, depth) {
	const pad = "  ".repeat(depth);
	const className = spec.$className || "Folder";
	if (spec.$path) {
		return folderItem(name, path.join(root, spec.$path), depth, className);
	}
	let xml = `${pad}<Item class="${className}" referent="${referent++}">\n`;
	xml += `${pad}  <Properties>\n${pad}    <string name="Name">${escapeXml(name)}</string>\n${pad}  </Properties>\n`;
	for (const [childName, childSpec] of Object.entries(spec)) {
		if (childName.startsWith("$")) continue;
		xml += node(childName, childSpec, depth + 1);
	}
	xml += `${pad}</Item>\n`;
	return xml;
}

const tree = project.tree;
const staticBlocks = {};
for (const name of ["Lighting", "Players", "SoundService", "Workspace"]) {
	staticBlocks[name] = topLevelBlock(previous, name);
}

// Ordre alphabétique des services, comme la sortie de Rojo.
const order = ["Lighting", "Players", "ReplicatedStorage", "ServerScriptService", "SoundService", "StarterPlayer", "Workspace"];
let body = "";
for (const service of order) {
	if (staticBlocks[service]) {
		// Les référents statiques sont renumérotés pour rester uniques.
		body += staticBlocks[service].replace(/referent="\d+"/g, () => `referent="${referent++}"`);
	} else {
		body += node(service, tree[service], 1);
	}
}

const xml = `<roblox version="4">\n${body}</roblox>`;
fs.writeFileSync(outPath, xml, "utf8");
const count = [...xml.matchAll(/<ProtectedString name="Source">/g)].length;
console.log(`Écrit ${path.relative(root, outPath)} : ${count} scripts, ${referent} instances.`);
