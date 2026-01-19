export type Struct<TFields extends Record<string, "boolean" | "float32" | "int32">> = {
  -readonly [TKey in keyof TFields]: FieldType[TFields[TKey]];
};

export type FieldType = { boolean: boolean; float32: number; int32: number };

export function createStruct<TFields extends Record<string, "boolean" | "float32" | "int32">>(
  wasmMemory: WebAssembly.Memory,
  baseOffset: number,
  fields: Readonly<TFields>,
): Struct<TFields> {
  const offsets = Object.fromEntries(
    Object.keys(fields).map((key, index) => [key, index * 4]),
  ) as Readonly<Record<keyof typeof fields, number>>;

  return new Proxy({} as Struct<TFields>, {
    get(_target, key) {
      const offset = baseOffset + offsets[key as keyof TFields];

      // Returns a fresh DataView into WASM memory because it can grow via `memory.grow()`
      const view = new DataView(wasmMemory.buffer);

      switch (fields[key as keyof TFields]) {
        case "boolean": {
          return view.getInt32(offset, true) !== 0;
        }
        case "float32": {
          return view.getFloat32(offset, true);
        }
        case "int32": {
          return view.getInt32(offset, true);
        }
      }
    },

    set(_target, key, newValue) {
      const offset = baseOffset + offsets[key as keyof TFields];
      const view = new DataView(wasmMemory.buffer);

      switch (fields[key as keyof TFields]) {
        case "boolean": {
          view.setInt32(offset, newValue ? 1 : 0, true);
          break;
        }
        case "float32": {
          view.setFloat32(offset, newValue, true);
          break;
        }
        case "int32": {
          view.setInt32(offset, newValue, true);
        }
      }

      return true;
    },
  });
}
