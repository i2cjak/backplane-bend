declare module "occt-import-js" {
  const factory: (module?: Record<string, unknown>) => Promise<{
    ReadStepFile(content: Uint8Array, params: Record<string, unknown> | null): any;
  }>;
  export default factory;
}
declare module "*.wasm" {
  const path: string;
  export default path;
}
