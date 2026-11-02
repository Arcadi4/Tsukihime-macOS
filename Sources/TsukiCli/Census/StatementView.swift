import Foundation
import TsukiCore
import TsukiEngine

final class StatementView {
    let statement: Statement
    let key: String
    let name: String
    private var textRanges: [ArgRange]?

    init(_ statement: Statement) {
        self.statement = statement
        self.key = statement.name.description
        if self.key.hasPrefix("ZM") {
            self.name = "ZM"
        } else {
            self.name = self.key
        }
    }

    var offset: Int { statement.offset }

    var textCount: Int {
        ensureText()
        return textRanges!.count
    }

    func textValue(_ i: Int) -> ByteSpan {
        ensureText()
        let r = textRanges![i]
        let slice = statement.args.slice(r.start, r.length)
        return ArgumentList.untagged(slice)
    }

    func textString(_ i: Int) -> String {
        latin1(textValue(i).toArray())
    }

    func inline16(_ i: Int) -> Int {
        InlineReader.readInt16(statement, i)
    }

    func expr(_ i: Int) -> Int? {
        let args = StageArgs(statement)
        guard args.has(i) else { return nil }
        return args.expr(i)
    }

    private func ensureText() {
        if textRanges == nil {
            var r: [ArgRange] = []
            _ = ArgumentList.split(statement.args, ArgumentList.startIn(statement), into: &r)
            textRanges = r
        }
    }
}
