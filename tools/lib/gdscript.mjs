// Shared GDScript text handling.
//
// Used by both the purity lint and the mutation harness: each needs to look at
// code without being fooled by a symbol that appears in a comment or a string.

// Replaces comments and string literals with spaces, preserving line structure
// and column positions so reported locations stay accurate.
export function stripCommentsAndStrings(source) {
  const out = [];
  let i = 0;

  while (i < source.length) {
    const rest = source.slice(i);
    const tripleMatch = /^("""|''')/.exec(rest);

    if (tripleMatch) {
      const quote = tripleMatch[1];
      const end = source.indexOf(quote, i + 3);
      const stop = end === -1 ? source.length : end + 3;
      for (; i < stop; i++) out.push(source[i] === "\n" ? "\n" : " ");
      continue;
    }

    const char = source[i];

    if (char === "#") {
      while (i < source.length && source[i] !== "\n") {
        out.push(" ");
        i++;
      }
      continue;
    }

    if (char === '"' || char === "'") {
      const quote = char;
      out.push(" ");
      i++;
      while (i < source.length && source[i] !== quote && source[i] !== "\n") {
        // Skip escaped characters so \" does not end the literal early.
        if (source[i] === "\\" && i + 1 < source.length) {
          out.push(" ");
          i++;
        }
        out.push(" ");
        i++;
      }
      if (i < source.length && source[i] === quote) {
        out.push(" ");
        i++;
      }
      continue;
    }

    out.push(char);
    i++;
  }

  return out.join("");
}


/// Walks a directory and returns every .gd file under it.
export function collectScripts(dir, readdirSync, statSync, join) {
  const found = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      found.push(...collectScripts(path, readdirSync, statSync, join));
    } else if (entry.endsWith(".gd")) {
      found.push(path);
    }
  }
  return found;
}
