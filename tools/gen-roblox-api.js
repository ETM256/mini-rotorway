// Génère tests/harness/api_data.luau à partir des définitions de types Roblox
// (luau-lsp : globalTypes.d.luau). Lancement manuel, résultat versionné :
//
//   node tools/gen-roblox-api.js /chemin/vers/globalTypes.d.luau
//
// Les définitions se téléchargent depuis
// https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
// Ce sont des DONNÉES (pas du code exécutable). Le fichier produit contient :
//   enums    : toutes les énumérations Roblox et leurs valeurs ;
//   creatable: les classes qu'Instance.new accepte ;
//   classes  : Object et tous les descendants d'Instance, avec parent direct,
//              propriétés (nom:type ; un type finissant par ? accepte nil),
//              méthodes et événements.
// Le harnais de test (tests/harness) et tools/check-roblox-api.js s'en servent
// pour refuser un Enum, une classe, une propriété ou une méthode invalide.

const fs = require("fs");
const path = require("path");

const defsPath = process.argv[2] || process.env.ROBLOX_DEFS;
if (!defsPath) {
  console.error("usage: node tools/gen-roblox-api.js <globalTypes.d.luau>");
  process.exit(1);
}

const text = fs.readFileSync(defsPath, "utf8");
const lines = text.split("\n");

const creatableMatch = lines[0].match(/"CREATABLE_INSTANCES":\s*\[([^\]]*)\]/);
const creatable = creatableMatch
  ? creatableMatch[1].split(",").map((s) => s.trim().replace(/^"|"$/g, "")).filter(Boolean)
  : [];

const types = new Map(); // name -> { parent, props:Map, methods:Set, events:Set }
let current = null;

for (const raw of lines) {
  const header = raw.match(/^declare extern type ([A-Za-z0-9_]+)(?: extends ([A-Za-z0-9_]+))? with(?: end)?\s*$/);
  if (header) {
    current = { parent: header[2] || null, props: new Map(), methods: new Set(), events: new Set(), items: [] };
    types.set(header[1], current);
    if (/ with end\s*$/.test(raw)) current = null;
    continue;
  }
  if (raw === "end") {
    current = null;
    continue;
  }
  if (!current) continue;
  const line = raw.trim();
  if (line === "" || line.startsWith("@")) continue;

  let m = line.match(/^function ([A-Za-z_][A-Za-z0-9_]*)\s*[(<]/);
  if (m) {
    current.methods.add(m[1]);
    continue;
  }
  m = line.match(/^(?:\["([^"]+)"\]|([A-Za-z_][A-Za-z0-9_]*)):\s*(.+)$/);
  if (m) {
    const name = m[1] || m[2];
    const type = m[3].trim();
    if (type.startsWith("RBXScriptSignal")) current.events.add(name);
    else current.props.set(name, type);
  }
}

// --- Enums : EnumFoo_INTERNAL extends Enum avec un membre par valeur.
const enums = {};
for (const [name, info] of types) {
  const m = name.match(/^Enum([A-Za-z0-9]+)_INTERNAL$/);
  if (!m || info.parent !== "Enum") continue;
  const items = [...info.props.keys()];
  enums[m[1]] = items;
}

// Valeurs qui existent dans Roblox mais manquent dans globalTypes.d.luau.
const EXTRA_ENUM_ITEMS = { KeyCode: ["Unknown"] };
for (const [enumName, items] of Object.entries(EXTRA_ENUM_ITEMS)) {
  if (!enums[enumName]) continue;
  for (const item of items) if (!enums[enumName].includes(item)) enums[enumName].push(item);
}

// --- Classes : tout ce qui descend d'Instance.
function isInstance(name) {
  const seen = new Set();
  let n = name;
  while (n && types.has(n) && !seen.has(n)) {
    if (n === "Instance") return true;
    seen.add(n);
    n = types.get(n).parent;
  }
  return false;
}

const classes = {};
for (const [name, info] of types) {
  if (/^Enum/.test(name) && name !== "EnumItem") continue;
  if (name !== "Object" && !isInstance(name)) continue;
  classes[name] = info;
}

// Tri stable pour que le fichier ne change que si l'API change.
const sorted = (iter) => [...iter].sort();
const q = (s) => JSON.stringify(s);

const out = [];
out.push("-- GENERATED par tools/gen-roblox-api.js depuis globalTypes.d.luau.");
out.push("-- Ne pas modifier à la main : relancer le générateur.");
out.push("return {");
out.push("\tcreatable = " + q(creatable.sort().join(" ")) + ",");
out.push("\tenums = {");
for (const name of sorted(Object.keys(enums))) {
  out.push("\t\t" + name + " = " + q(enums[name].join(" ")) + ",");
}
out.push("\t},");
out.push("\tclasses = {");
for (const name of sorted(Object.keys(classes))) {
  const c = classes[name];
  const props = sorted(c.props.keys()).map((k) => k.includes(" ") ? null : k + ":" + c.props.get(k).replace(/\s+/g, "")).filter(Boolean);
  const fields = ["parent = " + q(c.parent || "")];
  if (props.length) fields.push("props = " + q(props.join(" ")));
  if (c.methods.size) fields.push("methods = " + q(sorted(c.methods).join(" ")));
  if (c.events.size) fields.push("events = " + q(sorted(c.events).join(" ")));
  out.push("\t\t" + name + " = { " + fields.join(", ") + " },");
}
out.push("\t},");
out.push("}");

const target = path.join(__dirname, "..", "tests", "harness", "api_data.luau");
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, out.join("\n") + "\n", "utf8");
console.log(
  `api_data.luau : ${Object.keys(enums).length} enums, ${Object.keys(classes).length} classes, ` +
    `${creatable.length} classes créables, ${(fs.statSync(target).size / 1024).toFixed(0)} Ko`
);
