// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

// const startViewTransition =
//   document.startViewTransition?.bind(document) || ((cb: () => void) => cb())

type IdNode = {
  id: string
  name: string
  children: IdNode[]
}

type PatchType = keyof typeof Patches

type Patch = [
  id: string,
  name: PatchType,
  ...args: string[]
]

type PatchSet = Patch[]

export default class Runtime {
  #nodeSet = new NodeSet();

  apply(patches: PatchSet) {
    for (const patch of patches) {
      const [name, ...args] = patch;
      console.log("applyPatch", name, args)
      console.debug(name, args)
      const patchFn = Patches[name as PatchType] as any
      if (!patchFn) {
        throw new Error(`Not implemented: ${name}`)
      }
      patchFn.apply(this.#nodeSet, args as any);
    }
  }
}

class NodeSet {
  #nodes: Record<string, Node> = {};

  clear() {
    this.#nodes = {}
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
    const node = this.getNode(id)

    if (node instanceof HTMLElement) {
      return node
    }

    throw new Error(`Node ${id} is not an Element`)
  }

  getCharacterData(id: string) {
    const node = this.getNode(id)

    if (node instanceof CharacterData) {
      return node
    }

    throw new Error(`Node ${id} is not a CharacterData`)
  }
}

const Patches = {
  Initialize(this: NodeSet, tree: IdNode) {
    const visit = (domNode: Node, idNode: IdNode) => {
      if (!domNode) return;
      if (domNode.nodeName !== idNode.name) {
        console.error(`Node ${idNode.id} should be ${idNode.name}, but found ${domNode.nodeName}`)
      }
      this.setNode(idNode.id, domNode);
      if (!idNode.children) return;
      idNode.children.forEach((child, i) => {
        visit(domNode.childNodes[i], child);
      });
    };

    this.clear()
    visit(document.documentElement, tree)
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
    this.getElement(id).className = value
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
    console.log(state)
  },
} as const;
