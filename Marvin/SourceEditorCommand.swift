import Foundation
import XcodeKit

enum MarvinCommand: String {
  case selectCurrentWord
  case selectNextWord
  case selectPreviousWord
  case selectWordAbove
  case selectWordBelow
  case selectLineContents
  case joinLine
  case duplicateLine
  case deleteLine
  case moveToEOLandInsertLF
}

extension XCSourceTextPosition : Equatable {}

public func ==(lhs: XCSourceTextPosition, rhs: XCSourceTextPosition) -> Bool {
  return lhs.column == rhs.column && lhs.line == rhs.line
}

public func !=(lhs: XCSourceTextPosition, rhs: XCSourceTextPosition) -> Bool {
  return !(lhs == rhs)
}

extension UnicodeScalar {
  var isEmoji: Bool {
    switch value {
    case 0x1F600...0x1F64F, // Emoticons
    0x1F300...0x1F5FF, // Misc Symbols and Pictographs
    0x1F680...0x1F6FF, // Transport and Map
    0x2600...0x26FF,   // Misc symbols
    0x2700...0x27BF,   // Dingbats
    0xFE00...0xFE0F,   // Variation Selectors
    0x1F900...0x1F9FF,  // Supplemental Symbols and Pictographs
    65024...65039, // Variation selector
    8400...8447: // Combining Diacritical Marks for Symbols
      return true
    default: return false
    }
  }

  var isZeroWidthJoiner: Bool {

    return value == 8205
  }
}

extension String {

  subscript(i: Int) -> String {
    guard i >= 0 && i < count else { return "" }
    return String(self[index(startIndex, offsetBy: i)])
  }

  subscript(range: Range<Int>) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0,range.lowerBound), limitedBy: endIndex) ?? endIndex
    let upperIndex = index(lowerIndex, offsetBy: range.upperBound - range.lowerBound, limitedBy: endIndex) ?? endIndex
    return String(self[lowerIndex..<upperIndex])
  }

  subscript(range: ClosedRange<Int>) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0,range.lowerBound), limitedBy: endIndex) ?? endIndex
    let upperIndex = index(lowerIndex, offsetBy: range.upperBound - range.lowerBound + 1, limitedBy: endIndex) ?? endIndex
    return String(self[lowerIndex..<upperIndex])
  }

  subscript(textRange: XCSourceTextRange) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0, textRange.start.column), limitedBy: endIndex) ?? endIndex
    let upperIndex = index(lowerIndex, offsetBy: textRange.end.column - textRange.start.column + 1, limitedBy: endIndex) ?? endIndex
    return String(self[lowerIndex..<upperIndex])
  }
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
  static let validSet = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKOLMNOPQRSTUVWXYZÅÄÆÖØabcdefghijkolmnopqrstuvwxyzåäæöø_")
  static let spaceSet = CharacterSet(charactersIn: "  \n\t\r")

  func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) -> Void {
    // 🤔Implement your command here, invoking the completion handler when done. Pass it nil on success, and an NSError on failure.

    guard let identifier = invocation.commandIdentifier.components(separatedBy: ".").last,
      let command = MarvinCommand(rawValue: identifier)
      else {
        completionHandler(nil)
        return
    }

    guard let selection = invocation.buffer.selections.firstObject as? XCSourceTextRange, 
      selection.end.line < invocation.buffer.lines.count,
      let currentLine = invocation.buffer.lines[selection.end.line] as? String
      else { 
        completionHandler(nil)
        return 
    }
    
    var targetLine = currentLine

    switch command {
    case .selectCurrentWord:
      fallthrough
    case .selectNextWord:
      if !validate(line: currentLine[selection.end.column+1...currentLine.count]) {
        targetLine = findNextLine(currentSelection: selection, invocation: invocation)
      }
      selectWord(currentSelection: selection, currentLine: targetLine)
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
    case .selectPreviousWord:
      if !validate(line: currentLine[0..<max(selection.start.column-1, 0)]) {
        targetLine = findPreviousLine(currentSelection: selection, invocation: invocation)
      }
      selectPreviousWord(currentSelection: selection, currentLine: targetLine, completionHandler: completionHandler) {
        self.selectWord(currentSelection: selection, currentLine: targetLine)
        invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
      }
    case .selectWordAbove:
      if selection.start == selection.end {
        selectWord(currentSelection: selection, currentLine: targetLine)
        invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
        completionHandler(nil)
        return
      }

      guard let previousLine = invocation.buffer.lines[selection.start.line - 1] as? String else { break }
      targetLine = previousLine
      let position: CGFloat = CGFloat(selection.start.column) / CGFloat(currentLine.count)
      let newColumn = floor(CGFloat(previousLine.count) * position)
      selection.start.column = Int(newColumn)
      selection.start.line -= 1
      selection.end = selection.start
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])

      selectPreviousWord(currentSelection: selection, currentLine: targetLine, completionHandler: completionHandler) {
        self.selectWord(currentSelection: selection, currentLine: targetLine)
        invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
      }
    case .selectWordBelow:
      if selection.start == selection.end {
        selectWord(currentSelection: selection, currentLine: targetLine)
        invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
        completionHandler(nil)
        return
      }

      guard let nextLine = invocation.buffer.lines[selection.start.line + 1] as? String else { break }
      targetLine = nextLine
      let position: CGFloat = CGFloat(selection.start.column) / CGFloat(currentLine.count)
      let newColumn = floor(CGFloat(nextLine.count) * position)
      selection.start.column = Int(newColumn)
      selection.start.line += 1
      selection.end = selection.start
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])

      selectPreviousWord(currentSelection: selection, currentLine: targetLine, completionHandler: completionHandler) {
        self.selectWord(currentSelection: selection, currentLine: targetLine)
        invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
      }
    case .deleteLine:
      break
    case .duplicateLine:
      var padding = 0
      for index in selection.start.line...selection.end.line {
        invocation.buffer.lines.insert(invocation.buffer.lines[index + padding], at: selection.start.line)
        padding = padding + 1
      }
      break
    case .joinLine:
      break
    case .selectLineContents:
      guard let startLine = invocation.buffer.lines[selection.start.line] as? String
        else {
          completionHandler(nil)
          return
      }

      selection.start.column = 0
      for character in startLine {
        if !validate(character, inSet: SourceEditorCommand.spaceSet) {
          break
        }

        selection.start.column += 1
      }

      selection.end.column = currentLine.count

      for character in currentLine.reversed() {
        if !validate(character, inSet: SourceEditorCommand.spaceSet) {
          break
        }

        selection.end.column -= 1
      }

      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
    case .moveToEOLandInsertLF:
      guard let startLine = invocation.buffer.lines[selection.start.line] as? String
        else { completionHandler(nil); return }

      var padding = ""
      for character in startLine {
        if !validate(character, inSet: SourceEditorCommand.spaceSet) {
          break
        }

        padding += String(character)
      }

      invocation.buffer.lines.insert("\(padding)", at: selection.end.line + 1)

      selection.start.line += 1
      selection.start.column = padding.count
      selection.end = selection.start

      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
    }

    completionHandler(nil)
  }

  func selectPreviousWord(currentSelection: XCSourceTextRange, currentLine: String, completionHandler: @escaping (Error?) -> Void, completion: (() -> Void)? = nil) {
    guard let previousCharacter = currentLine[currentSelection.start.column - 1].first
      else {
        completionHandler(nil)
        return
    }

    currentSelection.start.column -= 1
    currentSelection.start.column -= amountOfEmoticonsInString(currentLine)

    currentSelection.end.column = currentSelection.start.column

    if !validate(previousCharacter, inSet: SourceEditorCommand.validSet) {
      for character in currentLine[0..<currentSelection.start.column].reversed() {
        let result = validate(character, inSet: SourceEditorCommand.validSet)
        if result {
          currentSelection.start.column -= 1
          break
        }
        currentSelection.start.column -= 1
      }
    }
    currentSelection.end = currentSelection.start
    completion?()
  }

  func selectWord(currentSelection: XCSourceTextRange, currentLine: String, completion: (() -> Void)? = nil) {
    guard let nextCharacter = currentLine[currentSelection.end.column + 1].first else {
      return
    }

    /// Check next character if text is selected
    if currentSelection.start != currentSelection.end {
      currentSelection.end.column += 2
      currentSelection.start = currentSelection.end
    }

    /// Find next valid letter
    if !validate(nextCharacter, inSet: SourceEditorCommand.validSet) {
      for character in currentLine[currentSelection.start.column..<currentLine.count] {
        if validate(character, inSet: SourceEditorCommand.validSet) {
          currentSelection.start.column += 1
          break
        }
        currentSelection.start.column += 1
      }
    }

    /// Search for beginning of word
    let startOfLine = currentLine[0..<currentSelection.start.column]
    let emoticons = amountOfEmoticonsInString(startOfLine)

    for character in startOfLine.reversed() {
      if !validate(character, inSet: SourceEditorCommand.validSet)  {
        break
      }
      currentSelection.start.column -= 1
    }

    currentSelection.end.column = currentSelection.start.column

    /// Search for end of word
    for character in currentLine[currentSelection.start.column..<currentLine.count] {
      if !validate(character, inSet: SourceEditorCommand.validSet) {
        break
      }
      currentSelection.end.column += 1
    }

    currentSelection.start.column += emoticons
    currentSelection.end.column += emoticons
    
    completion?()
  }
  
  func findPreviousLine(currentSelection: XCSourceTextRange, invocation: XCSourceEditorCommandInvocation) -> String {
    let lineRange = NSRange(location: 0, length: currentSelection.start.line)
    guard let previousLines: [String] = invocation.buffer.lines.subarray(with: lineRange) as? [String] 
      else { return "" }
    var newLine: String = ""
    var newLineSelection = currentSelection.start.line
    
    for line in previousLines.reversed() {
      if validate(line: line) {
        newLine = line
        break
      }
      newLineSelection -= 1
    }
    
    currentSelection.start.line = newLineSelection - 1
    currentSelection.end = currentSelection.start
    currentSelection.start.column = newLine.count - 1
    
    return newLine
  }
  
  func findNextLine(currentSelection: XCSourceTextRange, invocation: XCSourceEditorCommandInvocation) -> String {
    currentSelection.end.line += 1
    let lineRange = NSRange(location: currentSelection.end.line, length: invocation.buffer.lines.count - currentSelection.end.line)
    let remainingLines = invocation.buffer.lines.subarray(with: lineRange)
    var newLine: String = ""
    var newLineSelection = currentSelection.end.line
    
    for case let line as String in remainingLines {
      if validate(line: line) {
        newLine = line
        break
      }
      newLineSelection += 1
    }
    
    currentSelection.start.line = newLineSelection
    currentSelection.start.column = 0
    currentSelection.end = currentSelection.start
    
    return newLine
  }
  
  private func validate(line: String) -> Bool {
    return !line.filter({ validate($0, inSet: SourceEditorCommand.validSet) }).isEmpty
  }

  private func validate(_ character: Character, inSet set: CharacterSet) -> Bool {
    var found = false
    for ch in String(character).unicodeScalars {
      if set.contains(ch) || ch.isEmoji {
        found = true
        break
      }
    }
    return found
  }

  private func amountOfEmoticonsInString(_ string: String) -> Int {
    var result = 0
    for ch in string.unicodeScalars {
      if ch.isEmoji {
        result += 1
      }
    }
    return result
  }
}
