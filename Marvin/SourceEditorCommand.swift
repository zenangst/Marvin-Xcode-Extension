//
//  SourceEditorCommand.swift
//  Marvin
//
//  Created by Christoffer Winterkvist on 9/14/16.
//  Copyright © 2016 zenangst. All rights reserved.
//

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

extension String {

  subscript(i: Int) -> String {
    guard i >= 0 && i < characters.count else { return "" }
    return String(self[index(startIndex, offsetBy: i)])
  }

  subscript(range: Range<Int>) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0,range.lowerBound), limitedBy: endIndex) ?? endIndex
    return substring(with: lowerIndex..<(index(lowerIndex, offsetBy: range.upperBound - range.lowerBound, limitedBy: endIndex) ?? endIndex))
  }

  subscript(range: ClosedRange<Int>) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0,range.lowerBound), limitedBy: endIndex) ?? endIndex
    return substring(with: lowerIndex..<(index(lowerIndex, offsetBy: range.upperBound - range.lowerBound + 1, limitedBy: endIndex) ?? endIndex))
  }

  subscript(textRange: XCSourceTextRange) -> String {
    let lowerIndex = index(startIndex, offsetBy: max(0, textRange.start.column), limitedBy: endIndex) ?? endIndex

    return substring(with: lowerIndex..<(index(lowerIndex, offsetBy: textRange.end.column - textRange.start.column + 1, limitedBy: endIndex) ?? endIndex))
  }
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {

  static let validSet = NSCharacterSet(charactersIn: "0123456789ABCDEFGHIJKOLMNOPQRSTUVWXYZÅÄÆÖØabcdefghijkolmnopqrstuvwxyzåäæöø_")
  static let spaceSet = NSCharacterSet(charactersIn: "  \n\t\r")

  func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
    // Implement your command here, invoking the completion handler when done. Pass it nil on success, and an NSError on failure.

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
      if !validate(line: currentLine[selection.end.column+1...currentLine.characters.count]) {
        targetLine = findNextLine(currentSelection: selection, invocation: invocation)
      }
      selectWord(currentSelection: selection, currentLine: targetLine)
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
    case .selectPreviousWord:
      if !validate(line: currentLine[0...selection.start.column-1]) {
        targetLine = findPreviousLine(currentSelection: selection, invocation: invocation)
      }
      selectPreviousWord(currentSelection: selection, currentLine: targetLine) {
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
      let position: CGFloat = CGFloat(selection.start.column) / CGFloat(currentLine.characters.count)
      let newColumn = floor(CGFloat(previousLine.characters.count) * position)
      selection.start.column = Int(newColumn)
      selection.start.line -= 1
      selection.end = selection.start
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])

      selectPreviousWord(currentSelection: selection, currentLine: targetLine) {
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
      let position: CGFloat = CGFloat(selection.start.column) / CGFloat(currentLine.characters.count)
      let newColumn = floor(CGFloat(nextLine.characters.count) * position)
      selection.start.column = Int(newColumn)
      selection.start.line += 1
      selection.end = selection.start
      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])

      selectPreviousWord(currentSelection: selection, currentLine: targetLine) {
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
        else { completionHandler(nil); return }

      selection.start.column = 0
      for character in startLine.characters {
        if !validate(character, inSet: SourceEditorCommand.spaceSet) {
          break
        }

        selection.start.column += 1
      }

      selection.end.column = currentLine.characters.count

      for character in currentLine.characters.reversed() {
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
      for character in startLine.characters {
        if !validate(character, inSet: SourceEditorCommand.spaceSet) {
          break
        }

        padding += String(character)
      }

      invocation.buffer.lines.insert("\(padding)", at: selection.end.line + 1)

      selection.start.line += 1
      selection.start.column = padding.characters.count
      selection.end = selection.start

      invocation.buffer.selections.setArray([XCSourceTextRange(start: selection.start, end: selection.end)])
    }

    completionHandler(nil)
  }

  func selectPreviousWord(currentSelection: XCSourceTextRange, currentLine: String, completion: (() -> Void)? = nil) {
    guard let previousCharacter = currentLine[currentSelection.start.column - 1].characters.first
      else {
      return
    }

    currentSelection.start.column -= 1
    currentSelection.end.column = currentSelection.start.column

    if !validate(previousCharacter, inSet: SourceEditorCommand.validSet) {
      for character in currentLine[0..<currentSelection.start.column].characters.reversed() {
        if validate(character, inSet: SourceEditorCommand.validSet) {
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
    guard let nextCharacter = currentLine[currentSelection.end.column + 1].characters.first else { return }

    /// Check next character if text is selected
    if currentSelection.start != currentSelection.end {
      currentSelection.end.column += 2
      currentSelection.start = currentSelection.end
    }

    /// Find next valid letter
    if !validate(nextCharacter, inSet: SourceEditorCommand.validSet) {
      for character in currentLine[currentSelection.start.column..<currentLine.characters.count].characters {
        if validate(character, inSet: SourceEditorCommand.validSet) {
          currentSelection.start.column += 1
          break
        }
        currentSelection.start.column += 1
      }
    }

    /// Search for beginning of word
    for character in currentLine[0..<currentSelection.start.column].characters.reversed() {
      if !validate(character, inSet: SourceEditorCommand.validSet) {
        break
      }
      currentSelection.start.column -= 1
    }

    currentSelection.end.column = currentSelection.start.column

    /// Search for end of word
    for character in currentLine[currentSelection.start.column..<currentLine.characters.count].characters {
      if !validate(character, inSet: SourceEditorCommand.validSet) {
        break
      }
      currentSelection.end.column += 1
    }
    
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
    currentSelection.start.column = newLine.characters.count - 1
    
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
    return !line.characters.filter({ validate($0, inSet: SourceEditorCommand.validSet) }).isEmpty
  }

  private func validate(_ character: Character, inSet set: NSCharacterSet) -> Bool {
    var found = false
    for ch in String(character).utf16 {
      if set.characterIsMember(ch) { found = true; break }
    }
    return found
  }
}
