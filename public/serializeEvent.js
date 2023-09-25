// Copyright Andreas Alin <andreas.alin@gmail.com>
// License: AGPL-3.0

export default function serializeEvent(e) {
  const payload = {}

  payload.type = e.constructor.name;

  if (e.currentTarget) {
    payload.currentTarget = serializeElement(e.currentTarget);
  }

  if (e.target) {
    payload.target = serializeElement(e.target);
  }

  if (e instanceof MouseEvent) {
    payload.buttons = e.buttons;
  }

  if (e instanceof SubmitEvent) {
    if (e.submitter instanceof HTMLElement) {
      payload.submitter = serializeElement(e.submitter);
    }
  }

  return payload;
}

function serializeElement(obj) {
  if (obj instanceof HTMLFormElement) {
    const formData = Object.fromEntries(new FormData(obj).entries());

    return {
      tagName: obj.tagName,
      id: obj.id,
      method: obj.method,
      target: obj.target,
      name: obj.name,
      formData,
    };
  }

  if (obj instanceof HTMLSelectElement) {
    return {
      tagName: obj.tagName,
      id: obj.id,
      type: obj.type,
      name: obj.name,
      value: obj.value,
    };
  }

  if (obj instanceof HTMLDetailsElement) {
    return {
      tagName: obj.tagName,
      id: obj.id,
      open: obj.open,
    };
  }

  if (obj instanceof HTMLInputElement) {
    return {
      tagName: obj.tagName,
      id: obj.id,
      type: obj.type,
      name: obj.name,
      value: obj.value,
      checked: obj.checked,
    };
  }

  if (obj instanceof HTMLButtonElement) {
    return {
      tagName: obj.tagName,
      id: obj.id,
      type: obj.type,
      name: obj.name,
      value: obj.value,
    };
  }

  if (obj instanceof HTMLElement) {
    return {
      tagName: obj.tagName,
      id: obj.id,
    };
  }

  return {};
}
