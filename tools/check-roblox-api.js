// Contrôle statique de l'API Roblox utilisée par src/**/*.luau :
//   - Enum.X.Y        : l'énumération X existe et possède la valeur Y ;
//   - Instance.new("C"): C est une classe créable ;
//   - GetService("S")  : S est une classe Roblox connue.
// Les données viennent de tests/harness/api_data.luau (généré par
// tools/gen-roblox-api.js). Sortie : un "fichier:ligne" par erreur, code 1
// s'il y en a. Aurait détecté l'ancien Enum.ScrollDirection.
//
//   node tools/check-roblox-api.js [dossier-ou-fichier ...]   (défaut : src)

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const dataText = fs.readFileSync(path.join(root, "tests", "harness", "api_data.luau"), "utf8");

const enums = new Map();
const classes = new Set();
let creatable = new Set();
let section = "";
for (const line of dataText.split("\n")) {
  let m;
  if ((m = line.match(/^\tcreatable = "(.*)",$/))) {
    creatable = new Set(m[1].split(" ").filter(Boolean));
  } else if ((m = line.match(/^\t(enums|classes) = \{$/))) {
    section = m[1];
  } else if (/^\t\},$/.test(line)) {
    section = "";
  } else if (section === "enums" && (m = line.match(/^\t\t([A-Za-z0-9_]+) = "(.*)",$/))) {
    enums.set(m[1], new Set(m[2].split(" ").filter(Boolean)));
  } else if (section === "classes" && (m = line.match(/^\t\t([A-Za-z0-9_]+) = \{ parent/))) {
    classes.add(m[1]);
  }
}

// Remplace commentaires et contenu des chaînes par des espaces, en gardant
// les retours à la ligne : les numéros de ligne restent exacts. Les
// littéraux de chaîne sont conservés pour Instance.new("X") / GetService.
function stripComments(src) {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === "-" && src[i + 1] === "-") {
      const block = src.slice(i).match(/^--\[(=*)\[/);
      if (block) {
        const close = "]" + block[1] + "]";
        const end = src.indexOf(close, i + block[0].length);
        const stop = end === -1 ? n : end + close.length;
        out += src.slice(i, stop).replace(/[^\n]/g, " ");
        i = stop;
      } else {
        while (i < n && src[i] !== "\n") {
          out += " ";
          i++;
        }
      }
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && src[j] !== c && src[j] !== "\n") {
        if (src[j] === "\\") j++;
        j++;
      }
      out += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function walk(target, files) {
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const name of fs.readdirSync(target).sort()) walk(path.join(target, name), files);
  } else if (/\.luau$/.test(target)) {
    files.push(target);
  }
}

const targets = process.argv.length > 2 ? process.argv.slice(2) : [path.join(root, "src")];
const files = [];
for (const t of targets) walk(path.resolve(t), files);

let errors = 0;
function report(file, line, message) {
  console.log(`${path.relative(root, file)}:${line}: ${message}`);
  errors++;
}

for (const file of files) {
  const lines = stripComments(fs.readFileSync(file, "utf8")).split("\n");
  lines.forEach((line, index) => {
    const lineNo = index + 1;
    // Les chaînes (donc des noms entre guillemets) ne contiennent pas d'Enum.
    const code = line.replace(/"[^"]*"|'[^']*'/g, (s) => " ".repeat(s.length));
    for (const m of code.matchAll(/(?<![\w.])Enum\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?/g)) {
      const items = enums.get(m[1]);
      if (!items) {
        report(file, lineNo, `Enum.${m[1]} n'existe pas`);
      } else if (m[2] && !items.has(m[2]) && !["GetEnumItems", "FromName", "FromValue"].includes(m[2])) {
        report(file, lineNo, `Enum.${m[1]}.${m[2]} n'existe pas`);
      }
    }
    for (const m of line.matchAll(/Instance\.new\(\s*"([^"]+)"/g)) {
      if (!creatable.has(m[1])) report(file, lineNo, `Instance.new("${m[1]}") : classe non créable ou inconnue`);
    }
    for (const m of line.matchAll(/:GetService\(\s*"([^"]+)"/g)) {
      if (!classes.has(m[1])) report(file, lineNo, `GetService("${m[1]}") : service inconnu`);
    }
  });
}

if (errors > 0) {
  console.log(`check-roblox-api : ${errors} erreur(s) dans ${files.length} fichier(s)`);
  process.exit(1);
}
console.log(`check-roblox-api OK (${files.length} fichiers)`);
