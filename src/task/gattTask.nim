import std/asyncdispatch
import std/options
import std/strformat
import results
import nim_nucleus

type
  GattTaskObj = object
    id: int
    peer: PeerAddr
    gatt: Gatt
    device: BleDevice
  GattTask* = ref GattTaskObj

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc newGattTask*(id: int, gatt: Gatt, device: BleDevice): GattTask =
  new result
  result.id = id
  result.gatt = gatt
  result.device = device

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceName(self: GattTask): Future[Option[string]] {.async.} =
  const uuid = CharaUuid.DeviceName
  let handleValue_res = await self.gatt.readGattChar(uuid)
  if handleValue_res.isOk:
    let handleValue = handleValue_res.get()
    let deviceName = handleValue.value.toString()
    if deviceName.len > 0:
      result = some(deviceName)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc run*(self: GattTask) {.async.} =
  let bdAddress = self.gatt.bdAddress()
  echo &"* [TaskId: {self.id}]: device address: {bdAddress}"

  for i in countup(0, 10):
    let deviceName_opt = await self.getDeviceName()
    if deviceName_opt.isSome:
      let deviceName = deviceName_opt.get()
      echo &"* [TaskId: {self.id}]: [{i}] deviceName: {deviceName}"
    else:
      echo &"! [TaskId: {self.id}]: [{i}] get deviceName failed."
      break
    await sleepAsync(500)
  await self.gatt.disconnect()
  echo &"* [TaskId: {self.id}]: {bdAddress}: exit task."
