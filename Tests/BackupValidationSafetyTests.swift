import XCTest
@testable import LuqmaCore

final class BackupValidationSafetyTests:XCTestCase {
    private func snapshot(count:Int=700)throws->DiarySnapshot {
        var state=DiarySnapshot()
        let food=Food(catalogID:"validation-safety",name:"Oats",unit:.serving,nutrition:Nutrition(kcal:100,protein:10,carbs:15,fat:0),serving:"1 serving",source:"Your food")
        let start=try XCTUnwrap(DayKey.date("2025-01-01"))
        for index in 0..<count {
            let day=DayKey.string(start.addingTimeInterval(Double(index)*86400))
            state.entries.append(try DiaryEntry(food:food,amount:1,unit:.serving,meal:.breakfast,day:day,language:.en))
        }
        return state
    }
    func testLongHistoryPreservesStrictValidDatesAndRoundTrip()throws {
        var original=try snapshot()
        let first=try XCTUnwrap(original.entries.first)
        for _ in 0..<200 {var repeated=first;repeated.id=UUID();original.entries.append(repeated)}
        original.weights=[WeightReading(day:first.day,kg:80,source:"Manual")]
        let data=try Backup.encode(original)
        let restored=try Backup.decode(data)
        XCTAssertEqual(restored.entries,original.entries)
        XCTAssertEqual(restored.weights,original.weights)
        XCTAssertEqual(try Backup.encode(restored),data)
    }
    func testImpossibleDateStillRejectedAfterLongValidHistory()throws {
        var original=try snapshot()
        original.entries[original.entries.count-1].day="2026-02-30"
        XCTAssertThrowsError(try Backup.encode(original))
        original.entries[original.entries.count-1].day="2026-2-03"
        XCTAssertThrowsError(try Backup.encode(original))
    }
    func testRepeatedValidDateCannotBypassPerEntryNutritionAndQuantityChecks()throws {
        let original=try snapshot(count:1)
        var repeated=original.entries[0];repeated.id=UUID()
        var invalid=original;repeated.amount=0;invalid.entries.append(repeated)
        XCTAssertThrowsError(try Backup.encode(invalid))
        repeated.amount=1;repeated.kcal = .nan;invalid=original;invalid.entries.append(repeated)
        XCTAssertThrowsError(try Backup.encode(invalid))
    }
    func testDateSeenInFoodDoesNotBypassWeightValidation()throws {
        var original=try snapshot(count:1)
        let day=original.entries[0].day
        original.weights=[WeightReading(day:day,kg:Double.infinity,source:"Manual")]
        XCTAssertThrowsError(try Backup.encode(original))
        original.weights=[WeightReading(day:"2025-02-29",kg:80,source:"Manual")]
        XCTAssertThrowsError(try Backup.encode(original))
    }
}
