import { mkdirSync } from "fs";
import path from "path";
import { fileURLToPath, pathToFileURL } from "url";

const BACKEND_ROOT_URL = new URL("./", import.meta.url);
const DEFAULT_DATA_DIRECTORY_URL = new URL("./data/", BACKEND_ROOT_URL);

function resolveDirectoryURL(rawValue, fallbackURL = DEFAULT_DATA_DIRECTORY_URL) {
  const trimmed = String(rawValue || "").trim();
  if (!trimmed) return fallbackURL;

  const absolutePath = path.resolve(trimmed);
  const normalizedPath = absolutePath.endsWith(path.sep)
    ? absolutePath
    : `${absolutePath}${path.sep}`;
  return pathToFileURL(normalizedPath);
}

export const DATA_DIRECTORY_URL = resolveDirectoryURL(process.env.BACKEND_DATA_DIR);
export const DATA_DIRECTORY_PATH = fileURLToPath(DATA_DIRECTORY_URL);
export const MEDIA_DIRECTORY_URL = new URL("./media/", DATA_DIRECTORY_URL);
export const MEDIA_DIRECTORY_PATH = fileURLToPath(MEDIA_DIRECTORY_URL);

export function ensureDirectory(directoryURL) {
  mkdirSync(fileURLToPath(directoryURL), { recursive: true });
}

export function dataFileURL(filename) {
  return new URL(filename, DATA_DIRECTORY_URL);
}
