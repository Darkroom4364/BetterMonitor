//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation

guard let command = CLICommand.parse(CommandLine.arguments) else {
  exit(1)
}

let userInfo = command.userInfo
guard let replyId = userInfo[CLIKey.replyId] as? String else {
  exit(1)
}

class ReplyHandler: NSObject {
  let command: CLICommand
  var receivedReply = false

  init(command: CLICommand) {
    self.command = command
    super.init()
  }

  @objc func handleReply(_ notification: Notification) {
    receivedReply = true
    guard let resultString = notification.userInfo?["result"] as? String,
          let resultData = resultString.data(using: .utf8),
          let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
          let data = result["data"] as? [[String: Any]]
    else {
      CLICommand.printError("Invalid response from MonitorControl")
      exit(1)
    }

    if command.jsonOutput {
      if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
      }
    } else {
      formatOutput(action: command.action, property: command.property, data: data)
    }
    CFRunLoopStop(CFRunLoopGetMain())
  }
}

let handler = ReplyHandler(command: command)

DistributedNotificationCenter.default().addObserver(
  handler,
  selector: #selector(ReplyHandler.handleReply(_:)),
  name: NSNotification.Name(CLINotification.replyPrefix + replyId),
  object: nil,
  suspensionBehavior: .deliverImmediately
)

DistributedNotificationCenter.default().postNotificationName(
  NSNotification.Name(CLINotification.request),
  object: nil,
  userInfo: userInfo,
  deliverImmediately: true
)

// Run loop with 3-second timeout
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
  if !handler.receivedReply {
    CLICommand.printError("MonitorControl app is not running. Please launch MonitorControl first.")
    exit(1)
  }
}

CFRunLoopRun()
DistributedNotificationCenter.default().removeObserver(handler)
exit(0)

// MARK: - Output Formatting

func formatOutput(action: CLIAction, property: CLIProperty?, data: [[String: Any]]) {
  for item in data {
    if let error = item["error"] as? String {
      CLICommand.printError(error)
      continue
    }

    switch action {
    case .list:
      let name = item["name"] as? String ?? "Unknown"
      let id = item["id"] as? UInt32 ?? 0
      let type = item["type"] as? String ?? "unknown"
      let brightness = item["brightness"] as? Int ?? 0
      var line = "\(name) (id: \(id), type: \(type)) — brightness: \(brightness)%"
      if let volume = item["volume"] as? Int {
        line += ", volume: \(volume)%"
      }
      if let contrast = item["contrast"] as? Int {
        line += ", contrast: \(contrast)%"
      }
      print(line)

    case .get:
      let name = item["name"] as? String ?? "Unknown"
      let propName = property?.rawValue ?? ""
      if let value = item[propName] as? Int {
        print("\(name): \(propName) = \(value)%")
      }

    case .set:
      let name = item["name"] as? String ?? "Unknown"
      let propName = property?.rawValue ?? ""
      if let value = item[propName] as? Int {
        print("\(name): \(propName) set to \(value)%")
      }
    }
  }
}
