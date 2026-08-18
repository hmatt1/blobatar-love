// Lets `node --experimental-strip-types` import the upstream source, which uses
// extensionless relative imports that only a bundler resolves.
//
// It exists so the fixtures can be generated under V8 rather than under
// whatever runtime happens to be installed. That is not pedantry: `Math.hypot`
// differs by an ulp between V8 and JavaScriptCore on about a third of all
// inputs, so the two runtimes disagree about the twelfth decimal of a layout.
// See the note on `hypot` in `blobatar/util.lua`.
import { existsSync } from "fs";
import { fileURLToPath, pathToFileURL } from "url";

export async function resolve(specifier, context, next) {
  try {
    return await next(specifier, context);
  } catch (err) {
    if (!specifier.startsWith(".") && !specifier.startsWith("/")) throw err;
    const base = context.parentURL ? new URL(specifier, context.parentURL) : null;
    if (base) {
      for (const ext of [".ts", ".tsx", "/index.ts"]) {
        const candidate = new URL(base.href + ext);
        if (existsSync(fileURLToPath(candidate))) {
          return { url: candidate.href, shortCircuit: true };
        }
      }
    }
    throw err;
  }
}
