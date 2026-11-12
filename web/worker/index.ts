import { Downloads } from "./downloads";
import { Router } from "./router";

export interface Env {
  ASSETS: Fetcher;
  RELEASES: R2Bucket;
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    const router = new Router();
    new Downloads(env.RELEASES).register(router);

    return router.handle(request, () => env.ASSETS.fetch(request));
  },
} satisfies ExportedHandler<Env>;
