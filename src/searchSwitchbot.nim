import std/asyncdispatch
import std/enumutils
import std/options
import std/strformat
import std/strutils
import std/tables
import std/times
import results
import nim_nucleus
import ./task/gattTask

type
  DevType {.pure.} = enum
    Unknown = "?"
    Bot = "H"
    Meter = "T"
    Humidifier = "e"
    Curtain = "c"
    Curtain3 = "{"
    MotionSensor = "s"
    ContactSensor = "d"
    ColorBulb = "u"
    LedStripLight = "r"
    SmartLock = "o"
    PlugMini = "g"
    PlugMini2 = "j"
    MeterPlus = "i"
    SensorTag = "!"
  SwitchBot = object
    devType: DevType
    bleAddr: string
  AppObj = object
    ble: BleNim
    devices: Table[string, SwitchBot]
    tasks: seq[GattTask]
  App = ref AppObj

const
  CompanyId = 0x0969'u16
  UuidSwitchbot = 0xfd3d'u16

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc newApp(): App =
  new result
  result.ble = newBleNim(initialize = true)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc startStopScan(self: App, start: bool): Future[bool] {.async.} =
  const scanFilterPolicy = ScanFilterPolicy.AcceptAllExceptNotDirected
  result = await self.ble.startStopScan(active = true, enable = start,
      filterPolicy = scanFilterPolicy)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc handleDevice(self: App, device: BleDevice) {.async.} =
  if self.devices.hasKey(device.peerAddrStr):
    # SwitchBot device SCAN_RSP
    let uuid = device.advertiseData.getLe16(2)
    if uuid != UuidSwitchbot:
      self.devices.del(device.peerAddrStr)
      return
    try:
      let devType = parseEnum[DevType]($device.advertiseData.getU8(4).chr)
      echo &"Address: {device.peerAddrStr}, device: {devType.symbolName} found."
      let sbot = self.devices[device.peerAddrStr]
      if sbot.devType == DevType.Unknown:
        self.devices[device.peerAddrStr].devType = devType
        let gatt_res = await self.ble.connect(device, timeout = 200)
        if gatt_res.isOk:
          echo " ---> connected."
          discard await self.startStopScan(true)
          let gatt = gatt_res.get()
          let id = self.tasks.len + 1
          let task = newGattTask(id, gatt, device)
          self.tasks.add(task)
          asyncCheck task.run()
        else:
          echo "!! GATT connect failed."
    except:
      let errmsg = getCurrentExceptionMsg()
      echo errmsg
      return
  else:
    if device.manufacturerData.isNone:
      return
    let manData = device.manufacturerData.get()
    if manData.len < 2:
      return
    let companyId = manData.getLe16(0)
    echo &"Address: {device.peerAddrStr} (CompanyId: {companyId:04x}) found."
    if companyId == CompanyId:
      let sbot = SwitchBot(bleAddr: device.peerAddrStr, devType: DevType.Unknown)
      self.devices[device.peerAddrStr] = sbot
    elif companyId == 0x000d'u16:
      # TI
      if device.peerAddrStr.startsWith("C4:BE:84"):
        # SensorTag
        let stag = SwitchBot(bleAddr: device.peerAddrStr, devType: DevType.SensorTag)
        self.devices[device.peerAddrStr] = stag
        let gatt_res = await self.ble.connect(device, timeout = 200)
        if gatt_res.isOk:
          echo " ---> connected."
          discard await self.startStopScan(true)
          let gatt = gatt_res.get()
          let id = self.tasks.len + 1
          let task = newGattTask(id, gatt, device)
          self.tasks.add(task)
          asyncCheck task.run()
        else:
          echo "!! GATT connect failed."

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitAdvertising(self: App, timeout: int): Future[Table[string, SwitchBot]] {.async.} =
  self.devices.clear()
  let endTime = now().toTime.toUnixFloat() + timeout.float
  echo "waitAdvertising..."
  while true:
    let timeout = int((endTime - now().toTime.toUnixFloat()) * 1000.0)
    let dev_res = await self.ble.waitDevice(timeout = timeout)
    if dev_res.isErr:
      break
    let dev = dev_res.get()
    await self.handleDevice(dev)
  result = self.devices

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc main() {.async.} =
  let app = newApp()
  if not await app.startStopScan(start = true):
    echo "! failed to start scannning."
    return
  let devices = await app.waitAdvertising(timeout = 15)
  discard devices
  discard await app.startStopScan(start = false)

when isMainModule:
  waitFor main()
