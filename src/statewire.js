// =================================================================================================
// Binder
// =================================================================================================

/**
 * @typedef {(root: Element | Document) => () => void} Binder
 */

/**
 * @template TState
 * @template {Record<string, EventListener>} TActions
 * @param {Store<TState>} store
 * @param {TActions} actions
 * @returns {Binder}
 */
export const createBinder = (store, actions) => (root) => {
  const abortController = new AbortController();

  /** @type {((state: TState) => void)[]} */
  const setters = [];

  for (const element of root.querySelectorAll("[data-bind]")) {
    const bindings = element.getAttribute("data-bind")?.split(",");

    // /** @type {any} */ (element).hidden = true;

    if (!bindings) {
      continue;
    }

    for (const binding of bindings) {
      const [name, key] = /** @type {[ string, string]} */ (binding.trim().split(":"));
      const action = actions[key];

      if (action) {
        element.addEventListener(name, action, { signal: abortController.signal });
      } else {
        setters.push((state) => {
          /** @type {any} */ (element)[name] = /** @type {any} */ (state)[key];
        });
      }
    }
  }

  const unsubscribe = store.subscribe((state) => {
    for (const setter of setters) {
      setter(state);
    }
  });

  return () => {
    abortController.abort();
    unsubscribe();
  };
};

// =================================================================================================
// Store
// =================================================================================================

/**
 * @template TState
 * @typedef {object} Store
 * @property {() => TState} getState
 * @property {(callback: (state: TState) => TState) => void} publish
 * @property {(callback: (state: TState) => void) => () => void} subscribe
 */

/**
 * @template TState
 * @param {TState} initialState
 * @returns {Store<TState>}
 */
export const createStore = (initialState) => {
  /** @type {Set<(state: TState) => void>} */
  const subscribers = new Set();

  let state = initialState;

  return {
    getState: () => state,

    publish: (callback) => {
      const nextState = callback(state);

      if (!Object.is(nextState, state)) {
        state = nextState;

        for (const subscriber of subscribers) {
          subscriber(state);
        }
      }
    },

    subscribe: (callback) => {
      callback(state);
      subscribers.add(callback);

      return () => subscribers.delete(callback);
    },
  };
};
