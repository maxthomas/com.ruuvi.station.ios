import Foundation
import GRDB
import RxSwift
import RealmSwift

class RuuviTagRecordSubjectRxSwift {
    var sqlite: SQLiteContext
    var realm: RealmContext

    let subject: PublishSubject<[RuuviTagSensorRecord]> = PublishSubject()

    private var ruuviTagDataRealmToken: NotificationToken?
    private var ruuviTagDataRealmCache = [AnyRuuviTagSensorRecord]()
    private var ruuviTagDataTransactionObserver: TransactionObserver?
    
    deinit {
        ruuviTagDataRealmToken?.invalidate()
        subject.onCompleted()
    }

    init(ruuviTagId: String, sqlite: SQLiteContext, realm: RealmContext) {
        self.sqlite = sqlite
        self.realm = realm

        let request = RuuviTagDataSQLite.order(RuuviTagDataSQLite.dateColumn)
                                        .filter(RuuviTagDataSQLite.ruuviTagIdColumn == ruuviTagId)
        let observation = ValueObservation.tracking { db -> [RuuviTagDataSQLite] in
            try! request.fetchAll(db)
        }
        self.ruuviTagDataTransactionObserver = try! observation.start(in: sqlite.database.dbPool) { [weak self] records in
            self?.subject.onNext(records.map({ $0.any }))
        }

        let results = self.realm.main.objects(RuuviTagDataRealm.self)
                          .filter("ruuviTag.uuid == %@", ruuviTagId)
                          .sorted(byKeyPath: "date")
        self.ruuviTagDataRealmCache = results.compactMap({ $0.any })
        self.ruuviTagDataRealmToken = results.observe { [weak self] (change) in
            guard let sSelf = self else { return }
            switch change {
            case .initial(let records):
                if records.count > 0 {
                    sSelf.subject.onNext(records.compactMap({ $0.any }))
                }
            case .update(let records, _, let insertions, _):
                let newRecords = insertions.map({ records[$0] })
                if newRecords.count > 0 {
                    sSelf.subject.onNext(newRecords.compactMap({ $0.any }))
                }
            default:
                break
            }
        }
    }
}