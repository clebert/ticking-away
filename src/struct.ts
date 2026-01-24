// Primitive field types
type PrimitiveType = "boolean" | "float32" | "int32";

// Recursive field definition - can be primitive or nested struct
type FieldDef = PrimitiveType | { readonly [key: string]: FieldDef };

// Recursive type inference for the resulting struct
type StructType<T> = {
  -readonly [K in keyof T]: T[K] extends "boolean"
    ? boolean
    : T[K] extends "float32" | "int32"
      ? number
      : T[K] extends Record<string, FieldDef>
        ? StructType<T[K]>
        : never;
};

// Legacy exports for backwards compatibility
export type Struct<TFields extends Record<string, FieldDef>> = StructType<TFields>;
export type FieldType = { boolean: boolean; float32: number; int32: number };

// Calculate the byte size of a field definition
function fieldSize(def: FieldDef): number {
  if (typeof def === "string") return 4; // all primitives are 4 bytes (int32/float32)
  return Object.values(def).reduce((sum, d) => sum + fieldSize(d as FieldDef), 0);
}

// Calculate byte offsets for each field in a struct definition
function calculateOffsets(fields: Record<string, FieldDef>): Record<string, number> {
  const offsets: Record<string, number> = {};
  let offset = 0;
  for (const [key, def] of Object.entries(fields)) {
    offsets[key] = offset;
    offset += fieldSize(def);
  }
  return offsets;
}

export function createStruct<TFields extends Record<string, FieldDef>>(
  wasmMemory: WebAssembly.Memory,
  baseOffset: number,
  fields: Readonly<TFields>,
): StructType<TFields> {
  const offsets = calculateOffsets(fields as Record<string, FieldDef>);
  const subStructCache = new Map<string, StructType<Record<string, FieldDef>>>();

  return new Proxy({} as StructType<TFields>, {
    get(_target, key: string) {
      if (!(key in fields)) return undefined;

      const fieldDef = fields[key as keyof TFields];
      const fieldOffset = baseOffset + (offsets[key] ?? 0);

      // Nested struct - return cached sub-proxy
      if (typeof fieldDef === "object") {
        let cached = subStructCache.get(key);
        if (!cached) {
          cached = createStruct(wasmMemory, fieldOffset, fieldDef as Record<string, FieldDef>);
          subStructCache.set(key, cached);
        }
        return cached;
      }

      // Primitive - read from memory with fresh DataView (memory can grow)
      const view = new DataView(wasmMemory.buffer);

      switch (fieldDef) {
        case "boolean":
          return view.getInt32(fieldOffset, true) !== 0;
        case "float32":
          return view.getFloat32(fieldOffset, true);
        case "int32":
          return view.getInt32(fieldOffset, true);
        default:
          return undefined;
      }
    },

    set(_target, key: string, newValue) {
      if (!(key in fields)) return false;

      const fieldDef = fields[key as keyof TFields];
      const fieldOffset = baseOffset + (offsets[key] ?? 0);

      // Can't directly assign to nested struct
      if (typeof fieldDef === "object") {
        return false;
      }

      // Primitive - write to memory with fresh DataView (memory can grow)
      const view = new DataView(wasmMemory.buffer);

      switch (fieldDef) {
        case "boolean":
          view.setInt32(fieldOffset, newValue ? 1 : 0, true);
          break;
        case "float32":
          view.setFloat32(fieldOffset, newValue, true);
          break;
        case "int32":
          view.setInt32(fieldOffset, newValue, true);
      }

      return true;
    },
  });
}
