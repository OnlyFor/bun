import { test, expect, describe } from "bun:test";
import {
  readableStreamToBlob,
  readableStreamToArrayBuffer,
  readableStreamToBytes,
  readableStreamToText,
  readableStreamToJSON,
} from "bun";

describe("ByteBlobLoader", () => {
  const blobs = [
    ["Empty", new Blob()],
    ["Hello, world!", new Blob(["Hello, world!"], { type: "text/plain" })] as const,
    ["Bytes", new Blob([new Uint8Array([0x00, 0x01, 0x02, 0x03])], { type: "application/octet-stream" })] as const,
    [
      "Mixed",
      new Blob(["Hello, world!", new Uint8Array([0x00, 0x01, 0x02, 0x03])], { type: "multipart/mixed" }),
    ] as const,
  ] as const;

  describe.each([
    ["arrayBuffer", readableStreamToArrayBuffer] as const,
    ["bytes", readableStreamToBytes] as const,
    ["text", readableStreamToText] as const,
    ["blob", readableStreamToBlob] as const,
  ] as const)(`%s`, (name, fn) => {
    describe.each(blobs)(`%s`, (label, blob) => {
      test("works", async () => {
        const stream = blob.stream();
        const result = fn(stream);
        console.log(Promise, result);
        expect(result.then).toBeFunction();
        const awaited = await result;
        expect(awaited).toEqual(await new Response(blob)[name]());
      });
    });
  });

  test("json", async () => {
    const blob = new Blob(['"Hello, world!"'], { type: "application/json" });
    const stream = blob.stream();
    const result = readableStreamToJSON(stream);
    expect(result.then).toBeFunction();
    const awaited = await result;
    expect(awaited).toStrictEqual(await new Response(blob).json());
  });

  test("returns a rejected Promise for invalid JSON", async () => {
    const blob = new Blob(["I AM NOT JSON!"], { type: "application/json" });
    const stream = blob.stream();
    const result = readableStreamToJSON(stream);
    expect(result.then).toBeFunction();
    expect(async () => await result).toThrow();
  });
});