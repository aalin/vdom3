// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

export default class Runtime {
  #nodeSet = new NodeSet();

  constructor(tree) {
    const visit = (domNode, idNode) => {
      if (!domNode) return;
      this.#nodeSet.setNode(idNode.id, domNode);
      if (!idNode.children) return;
      idNode.children.forEach((child, i) => {
        visit(domNode.childNodes[i], child);
      });
    };

    visit(document.documentElement, tree);
  }

  apply(patch) {
    const [name, ...args] = patch;
    Patches[name].apply(this.#nodeSet, args);
  }
}

class NodeSet {
  #nodes = {};

  deleteNode(id) {
    delete this.#nodes[id];
  }

  setNode(id, node) {
    this.#nodes[id] = node;
  }

  getNode(id) {
    const node = this.#nodes[id];

    if (!node) {
      throw new Error(`Node not found: ${id}`);
    }

    return node;
  }

  getNodes(ids) {
    return ids.map((id) => this.getNode(id));
  }
}

const Patches = {
  CreateElement(id, type) {
    this.setNode(id, document.createElement(type));
  },
  CreateTextNode(id, content) {
    this.setNode(id, document.createTextNode(content));
  },
  CreateComment(id, content) {
    this.setNode(id, document.createComment(content));
  },
  RemoveNode(id) {
    this.deleteNode(id);
  },
  SetAttribute(id, name, value) {
    this.getNode(id).setAttribute(name, value);
  },
  RemoveAttribute(id, name) {
    this.getNode(id).removeAttribute(name);
  },
  SetCSSProperty(id, name, value) {
    this.getNode(id).style.setProperty(name, value);
  },
  RemoveCSSProperty(id, name) {
    this.getNode(id).style.removeProperty(name);
  },
  SetTextContent(id, content) {
    this.getNode(id).data = content;
  },
  ReplaceChildren(id, childIds) {
    this.getNode(id).replaceChildren(...this.getNodes(childIds));
  },
};
