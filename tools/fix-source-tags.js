// Roblox Studio écrit le Source des scripts en <ProtectedString>.
// Rojo écrit <string> : on aligne la sortie sur le format de Studio.
const fs = require("fs");

const path = process.argv[2];
if (!path) {
  console.error("usage: node fix-source-tags.js <fichier.rbxlx>");
  process.exit(1);
}

const xml = fs.readFileSync(path, "utf8").replace(
  /<string name="Source"><!\[CDATA\[([\s\S]*?)\]\]><\/string>/g,
  '<ProtectedString name="Source"><![CDATA[$1]]></ProtectedString>'
);

fs.writeFileSync(path, xml, "utf8");

const count = [...xml.matchAll(/<ProtectedString name="Source">/g)].length;
console.log(`Sources converties : ${count}`);
