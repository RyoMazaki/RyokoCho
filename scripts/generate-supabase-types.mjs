import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const cli = fileURLToPath(
  new URL("../node_modules/supabase/dist/supabase.js", import.meta.url),
);
const result = spawnSync(
  process.execPath,
  [cli, "gen", "types", "typescript", "--linked", "--schema", "public"],
  { cwd: root, encoding: "utf8", stdio: ["inherit", "pipe", "inherit"] },
);

if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
if (!result.stdout.includes("export type Database =")) {
  throw new Error("Supabase CLI did not return Database types; existing file preserved.");
}

const directory = new URL("../src/types/", import.meta.url);
mkdirSync(directory, { recursive: true });
writeFileSync(new URL("database.types.ts", directory), result.stdout, "utf8");
console.log("Generated src/types/database.types.ts from the linked Supabase project.");