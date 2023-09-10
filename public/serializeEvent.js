export default function serializeEvent(event) {
  return {
    type: event.type,
    value: event.target.value,
  }
}
