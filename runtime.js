export default class Runtime {
  constructor(root) {
    this.nodes = {}

    const visit = (node, idNode) => {
      if (!node) return
      this.nodes[idNode.id] = node
      console.log(idNode.children)
      if (!idNode.children) return
      idNode.children.forEach((child, i) => {
        console.log(child, node.childNodes[i])
        visit(node.childNodes[i], child)
      })
    }

    visit(document.documentElement, root)
    console.log("Nodes", this.nodes)
  }

  getNode(id) {
    const node = this.nodes[id]

    if (!node) {
      throw new Error(`Node not found: ${id}`)
    }

    return node
  }

  CreateElement(id, type) {
    this.nodes[id] = document.createElement(type)
  }

  CreateTextNode(id, content) {
    this.nodes[id] = document.createTextNode(content)
  }

  CreateComment(id, content) {
    this.nodes[id] = document.createComment(content)
  }

  RemoveNode(id) {
    delete this.nodes[id]
  }

  SetAttribute(id, name, value) {
    this.nodes[id].setAttribute(name, value)
  }

  RemoveAttribute(id, name) {
    this.nodes[id].removeAttribute(name)
  }

  SetCSSProperty(id, name, value) {
    this.nodes[id].styles.setProperty(name, value)
  }

  RemoveCSSProperty(id, name) {
    this.nodes[id].styles.removeProperty(name)
  }

  SetTextContent(id, content) {
    this.nodes[id].data = content
  }

  ReplaceChildren(id, childIds) {
    const children = childIds.map((childId) => this.nodes[childId])
    this.nodes[id].replaceChildren(...children)
  }
}
