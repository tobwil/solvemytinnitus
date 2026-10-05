export type Params = Record<string, string>;

export function parseHash(): { path: string; params: Params } {
  const raw = location.hash.replace(/^#/, '') || '/';
  const [path, q] = raw.split('?');
  const params: Params = {};
  if (q) for (const [k, v] of new URLSearchParams(q)) params[k] = v;
  return { path: path || '/', params };
}

export function navigate(path: string): void {
  if (location.hash === `#${path}`) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = path;
}

export function back(fallback = '/'): void {
  if (history.length > 1) history.back();
  else navigate(fallback);
}
