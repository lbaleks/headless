import fs from "fs";
import path from "path";

const DATA_DIR = path.join(process.cwd(), ".data");
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

function fileFor(name: string) {
  return path.join(DATA_DIR, name + ".json");
}

export function readJson<T>(name: string, fallback: T): T {
  const f = fileFor(name);
  try {
    const raw = fs.readFileSync(f, "utf8");
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export function writeJson<T>(name: string, data: T) {
  const f = fileFor(name);
  fs.writeFileSync(f, JSON.stringify(data, null, 2));
}

export function uid() {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
