import { effect, type ReadonlySignal, type Signal } from "@preact/signals-core";

type SignalValue = Signal<unknown> | ReadonlySignal<unknown>;
type StoreValue = SignalValue | EventListener;
type Store = Record<string, StoreValue>;
type Stores = Record<string, Store>;

export interface BinderConfig {
  stores: Stores;
}

export function createBinder(config: BinderConfig): (root: Element | Document) => () => void {
  const { stores } = config;

  function resolve(path: string): StoreValue | undefined {
    const dotIndex = path.indexOf(".");

    if (dotIndex === -1) {
      console.error(
        `[binder] Invalid path "${path}": missing dot separator (expected "store.key")`,
      );

      return undefined;
    }

    const storeName = path.slice(0, dotIndex);
    const key = path.slice(dotIndex + 1);

    if (!key) {
      console.error(`[binder] Invalid path "${path}": missing key after dot`);

      return undefined;
    }

    const store = stores[storeName];

    if (!store) {
      console.error(`[binder] Unknown store "${storeName}" in path "${path}"`);

      return undefined;
    }

    const value = store[key];

    if (value === undefined) {
      console.error(`[binder] Unknown key "${key}" in store "${storeName}"`);

      return undefined;
    }

    return value;
  }

  return function bind(root: Element | Document): () => void {
    const disposers: (() => void)[] = [];

    for (const element of root.querySelectorAll("[data-bind]")) {
      const bindings = element.getAttribute("data-bind")?.split(",") ?? [];

      for (const binding of bindings) {
        const colonIndex = binding.indexOf(":");

        if (colonIndex === -1) {
          console.error(
            `[binder] Invalid binding "${binding}": missing colon separator (expected "prop:store.key")`,
          );

          continue;
        }

        const prop = binding.slice(0, colonIndex).trim();
        const path = binding.slice(colonIndex + 1).trim();

        if (!prop) {
          console.error(
            `[binder] Invalid binding "${binding}": missing property name before colon`,
          );

          continue;
        }

        if (!path) {
          console.error(`[binder] Invalid binding "${binding}": missing path after colon`);

          continue;
        }

        const isNegated = path.startsWith("!");
        const cleanPath = isNegated ? path.slice(1) : path;
        const value = resolve(cleanPath);

        if (value === undefined) {
          continue;
        }

        if (typeof value === "function") {
          if (isNegated) {
            console.error(`[binder] Cannot negate event listener "${cleanPath}"`);

            continue;
          }

          const eventProp = `on${prop}`;

          if (!(eventProp in element)) {
            console.error(`[binder] Unknown event "${prop}" on <${element.tagName.toLowerCase()}>`);

            continue;
          }

          const abortController = new AbortController();

          element.addEventListener(prop, value as EventListener, {
            signal: abortController.signal,
          });

          disposers.push(() => abortController.abort());

          continue;
        }

        if (!(prop in element)) {
          console.error(
            `[binder] Unknown property "${prop}" on <${element.tagName.toLowerCase()}>`,
          );

          continue;
        }

        disposers.push(
          effect(() => {
            (element as unknown as Record<string, unknown>)[prop] = isNegated
              ? !value.value
              : value.value;
          }),
        );
      }
    }

    return () => {
      for (const dispose of disposers) {
        dispose();
      }
    };
  };
}
