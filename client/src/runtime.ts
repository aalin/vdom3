// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

// const startViewTransition =
//   document.startViewTransition?.bind(document) || ((cb: () => void) => cb())

type IdNode = {
  id: string;
  name: string;
  children: IdNode[];
};

type PatchType = keyof typeof Patches;

type Patch = [id: string, name: PatchType, ...args: string[]];

type PatchSet = Patch[];

export default class Runtime {
  #nodeSet = new NodeSet();

  apply(patches: PatchSet) {
    for (const patch of patches) {
      const [name, ...args] = patch;
      console.log("applyPatch", name, args);
      console.debug(name, args);
      const patchFn = Patches[name as PatchType] as any;
      if (!patchFn) {
        throw new Error(`Not implemented: ${name}`);
      }
      patchFn.apply(this.#nodeSet, args as any);
    }
  }
}

class NodeSet {
  #nodes: Record<string, Node> = {};

  clear() {
    this.#nodes = {};
  }

  deleteNode(id: string) {
    delete this.#nodes[id];
  }

  setNode(id: string, node: Node) {
    this.#nodes[id] = node;
  }

  getNode(id: string) {
    const node = this.#nodes[id];

    if (!node) {
      throw new Error(`Node not found: ${id}`);
    }

    return node;
  }

  getNodes(ids: string[]) {
    return ids.map((id) => this.getNode(id));
  }

  getElement(id: string) {
    const node = this.getNode(id);

    if (node instanceof HTMLElement) {
      return node;
    }

    throw new Error(`Node ${id} is not an Element`);
  }

  getCharacterData(id: string) {
    const node = this.getNode(id);

    if (node instanceof CharacterData) {
      return node;
    }

    throw new Error(`Node ${id} is not a CharacterData`);
  }
}

const Patches = {
  Initialize(this: NodeSet, tree: IdNode) {
    const visit = (domNode: Node, idNode: IdNode) => {
      if (!domNode) return;
      if (domNode.nodeName !== idNode.name) {
        console.error(
          `Node ${idNode.id} should be ${idNode.name}, but found ${domNode.nodeName}`,
        );
      }
      this.setNode(idNode.id, domNode);
      if (!idNode.children) return;
      idNode.children.forEach((child, i) => {
        visit(domNode.childNodes[i], child);
      });
    };

    this.clear();
    visit(document.documentElement, tree);
  },
  CreateElement(this: NodeSet, id: string, type: string) {
    this.setNode(id, document.createElement(type));
  },
  CreateTextNode(this: NodeSet, id: string, content: string) {
    this.setNode(id, document.createTextNode(content));
  },
  CreateComment(this: NodeSet, id: string, content: string) {
    this.setNode(id, document.createComment(content));
  },
  RemoveNode(this: NodeSet, id: string) {
    this.deleteNode(id);
  },
  SetClassName(this: NodeSet, id: string, value: string) {
    this.getElement(id).className = value;
  },
  SetAttribute(this: NodeSet, id: string, name: string, value: string) {
    this.getElement(id).setAttribute(name, value);
  },
  RemoveAttribute(this: NodeSet, id: string, name: string) {
    this.getElement(id).removeAttribute(name);
  },
  SetCSSProperty(this: NodeSet, id: string, name: string, value: string) {
    this.getElement(id).style.setProperty(name, value);
  },
  RemoveCSSProperty(this: NodeSet, id: string, name: string) {
    this.getElement(id).style.removeProperty(name);
  },
  SetTextContent(this: NodeSet, id: string, content: string) {
    this.getCharacterData(id).data = content;
  },
  ReplaceChildren(this: NodeSet, id: string, childIds: string[]) {
    this.getElement(id).replaceChildren(...this.getNodes(childIds));
  },
  Transfer(this: NodeSet, state: Blob) {
    console.log(state);
  },
  AddStyleSheet(this: NodeSet, path: string) {
    console.error(path);
    console.error(path);
    console.error(path);
    console.error(path);
    console.error(path);
    console.error(path);
    console.error(path);
  },
  RenderError(
    this: NodeSet,
    file: string,
    type: string,
    message: string,
    backtrace: string[],
    source: string,
    treePath: { name: string; path?: string }[],
  ) {
    const formats = [];
    const buf = [];

    buf.push(`%c${type}: ${message}`);
    formats.push("font-size: 1.25em");

    treePath.forEach((path, i) => {
      const indent = "  ".repeat(i);
      if (path.path) {
        buf.push(`%c${indent}%%%c${path.name} %c(${path.path})`);
        formats.push("color: deeppink;", "color: deepskyblue;", "color: gray;");
      } else {
        buf.push(`%c${indent}%%%c${path.name}`);
        formats.push("color: deeppink;", "color: deepskyblue;");
      }
    });

    backtrace.forEach((line) => {
      buf.push(`%c${line}`);

      formats.push(
        line.startsWith(`${file}:`)
          ? "font-size: 1em; font-weight: 600; text-shadow: 0 0 3px #000;"
          : "font-size: 1em;",
      );
    });

    console.error(buf.join("\n"), ...formats);

    const existing = Array.from(
      document.getElementsByTagName("mayu-exception"),
    );
    existing.forEach((e) => {
      e.remove();
    });

    const element =
      document.getElementsByTagName("mayu-exception")[0] ||
      document.createElement("mayu-exception");

    const interestingLines = new Set<number>();

    backtrace.forEach((line) => {
      if (line.startsWith(`${file}:`)) {
        interestingLines.add(Number(line.split(":")[1]));
      }
    });

    console.log("INTERESTING LINES", interestingLines);

    element.replaceChildren(
      h("span", [`${type}: ${message}`], { slot: "title" }),
      ...treePath.map((path, i) =>
        h(
          "li",
          [
            h("span", ["  ".repeat(i)]),
            h("span", ["%"], { style: "color: deeppink;" }),
            h("span", [path.name], { style: "color: deepskyblue;" }),
            " ",
            path.path &&
              h("span", [`(${path.path})`], { style: "opacity: 50%;" }),
          ],
          { slot: "tree-path" },
        ),
      ),
      ...backtrace.map((line) =>
        h(
          "li",
          [
            line.startsWith(`${file}:`)
              ? h("strong", [line], { style: "color: red;" })
              : line,
          ],
          {
            slot: "backtrace",
          },
        ),
      ),
      ...source.split("\n").map((line, i) =>
        h(
          "li",
          [
            interestingLines.has(i + 1)
              ? h("strong", [line], { style: "color: red;" })
              : line,
          ],
          {
            slot: "source",
          },
        ),
      ),
    );
    console.log("FILE", file);

    document.body.appendChild(element);
  },
} as const;

import h from "./h";
