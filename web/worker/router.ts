export type Params = Record<string, string>;
export type Handler = (request: Request, params: Params) => Response | Promise<Response>;

interface Route {
  method: string;
  pattern: RegExp;
  names: string[];
  handler: Handler;
}

/** Matches requests to handlers by method and path, with `:name` segments passed as params. */
export class Router {
  private readonly routes: Route[] = [];

  on(method: string, path: string, handler: Handler): this {
    const names: string[] = [];
    const source = path.replace(/:(\w+)/g, (_, name: string) => {
      names.push(name);

      return "([^/]+)";
    });

    this.routes.push({ method, pattern: new RegExp(`^${source}$`), names, handler });

    return this;
  }

  get(path: string, handler: Handler): this {
    return this.on("GET", path, handler);
  }

  post(path: string, handler: Handler): this {
    return this.on("POST", path, handler);
  }

  async handle(request: Request, fallback: () => Promise<Response>): Promise<Response> {
    const path = new URL(request.url).pathname;
    const method = request.method === "HEAD" ? "GET" : request.method;

    for (const route of this.routes) {
      const match = route.method === method ? route.pattern.exec(path) : null;
      if (!match) continue;

      const params = Object.fromEntries(route.names.map((name, i) => [name, decodeURIComponent(match[i + 1])]));

      return route.handler(request, params);
    }

    return fallback();
  }
}
