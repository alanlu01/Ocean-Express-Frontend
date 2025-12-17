import Foundation
import CoreLocation

struct DeliveryDestination: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double?
    let longitude: Double?

    init(name: String, latitude: Double?, longitude: Double?) {
        self.id = name
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct DeliveryLocationCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let destinations: [DeliveryDestination]
}

enum DeliveryCatalog {
    static let demoCategories: [DeliveryLocationCategory] = [
        DeliveryLocationCategory(
            name: "校園示範",
            destinations: [
                DeliveryDestination(name: "行政大樓", latitude: 25.1503372, longitude: 121.7655292),
                DeliveryDestination(name: "展示廳", latitude: 25.1122988, longitude: 121.6126358),
                DeliveryDestination(name: "圖書館", latitude: 25.1501305, longitude: 121.7753758),
                DeliveryDestination(name: "綜合研究中心", latitude: 25.0862517, longitude: 121.6591193),
                DeliveryDestination(name: "綜合二館", latitude: 25.1505525, longitude: 121.7749731),
                DeliveryDestination(name: "宏廣書屋", latitude: 25.0973044, longitude: 121.6428422),
                DeliveryDestination(name: "郵局", latitude: 25.1506004, longitude: 121.7758124),
                DeliveryDestination(name: "機械B館", latitude: 25.1454902, longitude: 121.7869715),
                DeliveryDestination(name: "機械A館", latitude: 25.1505385, longitude: 121.778163),
                DeliveryDestination(name: "育樂館", latitude: 25.1494738, longitude: 121.7771712),
                DeliveryDestination(name: "商船系館", latitude: 25.1497084, longitude: 121.7776317),
                DeliveryDestination(name: "延平技術大樓", latitude: 25.1499251, longitude: 121.7776824),
                DeliveryDestination(name: "輪機實習工廠", latitude: 25.0844931, longitude: 121.6244598),
                DeliveryDestination(name: "沛華大樓", latitude: 25.1497201, longitude: 121.7781734),
                DeliveryDestination(name: "航管系館", latitude: 25.1495217, longitude: 121.7783699),
                DeliveryDestination(name: "勇泉", latitude: 25.1484119, longitude: 121.7790699),
                DeliveryDestination(name: "海空大樓", latitude: 25.1495485, longitude: 121.7788197),
                DeliveryDestination(name: "游泳運動中心", latitude: 25.0820998, longitude: 121.6616511),
                DeliveryDestination(name: "第四宿舍", latitude: 25.1486255, longitude: 121.77917),
                DeliveryDestination(name: "第二餐廳", latitude: 25.1485298, longitude: 121.7791256),
                DeliveryDestination(name: "第三宿舍", latitude: 25.1486263, longitude: 121.7787136),
                DeliveryDestination(name: "學生活動中心", latitude: 25.1491197, longitude: 121.7762996),
                DeliveryDestination(name: "體育館", latitude: 25.1494738, longitude: 121.7771712),
                DeliveryDestination(name: "運動場", latitude: 25.1494738, longitude: 121.7771712),
                DeliveryDestination(name: "籃球場", latitude: 25.1494738, longitude: 121.7771712),
                DeliveryDestination(name: "海大意象館", latitude: 25.1452842, longitude: 121.7869715),
                DeliveryDestination(name: "小艇碼頭", latitude: 25.1517895, longitude: 121.775311),
                DeliveryDestination(name: "第二宿舍", latitude: 25.1465545, longitude: 121.7728215),
                DeliveryDestination(name: "射箭場", latitude: 24.6746528, longitude: 121.1640908),
                DeliveryDestination(name: "第一餐廳", latitude: 25.0822802, longitude: 121.6570966),
                DeliveryDestination(name: "綜合三館", latitude: 25.1490421, longitude: 121.7752189),
                DeliveryDestination(name: "龍崗生態園區", latitude: 25.1481301, longitude: 121.7754562),
                DeliveryDestination(name: "夢泉", latitude: 25.1488362, longitude: 121.7751857),
                DeliveryDestination(name: "人文大樓", latitude: 25.1498248, longitude: 121.7750303),
                DeliveryDestination(name: "山海迴廊", latitude: 25.1660964, longitude: 121.6126358),
                DeliveryDestination(name: "第一宿舍", latitude: 25.1487384, longitude: 121.7738906),
                DeliveryDestination(name: "景觀公園", latitude: 25.1133526, longitude: 121.6715195),
                DeliveryDestination(name: "海事大樓乙棟", latitude: 25.1489988, longitude: 121.7736823),
                DeliveryDestination(name: "海事大樓甲棟", latitude: 25.1493783, longitude: 121.7756341),
                DeliveryDestination(name: "創校紀念公園", latitude: 25.0972093, longitude: 121.6126358),
                DeliveryDestination(name: "海事大樓丙棟", latitude: 25.1496471, longitude: 121.7737298),
                DeliveryDestination(name: "校史博物館", latitude: 25.1497764, longitude: 121.7740803),
                DeliveryDestination(name: "環態所館", latitude: 25.1492422, longitude: 121.7736156),
                DeliveryDestination(name: "養殖溫室", latitude: 25.0859117, longitude: 121.6565365),
                DeliveryDestination(name: "綜合一館", latitude: 25.1495579, longitude: 121.7730681),
                DeliveryDestination(name: "海洋系館", latitude: 25.0842117, longitude: 121.6705447),
                DeliveryDestination(name: "食安所館", latitude: 25.1501214, longitude: 121.7735711),
                DeliveryDestination(name: "排球場", latitude: 25.1494738, longitude: 121.7771712),
                DeliveryDestination(name: "環漁系館", latitude: 25.1495309, longitude: 121.7721138),
                DeliveryDestination(name: "生命科學院館", latitude: 25.0829833, longitude: 121.6672501),
                DeliveryDestination(name: "食品工程館", latitude: 25.1507155, longitude: 121.7730126),
                DeliveryDestination(name: "陸生動物實驗中心", latitude: 25.1508623, longitude: 121.7732889),
                DeliveryDestination(name: "食品科學系館", latitude: 25.0823386, longitude: 121.6562766),
                DeliveryDestination(name: "木蘭海洋海事教育大樓", latitude: 25.1513789, longitude: 121.7716621),
                DeliveryDestination(name: "雨水公園", latitude: 25.0228265, longitude: 121.5254656),
                DeliveryDestination(name: "海洋工程綜合實驗館", latitude: 25.0837925, longitude: 121.6688633),
                DeliveryDestination(name: "壘球場", latitude: 25.2155255, longitude: 121.6779919),
                DeliveryDestination(name: "河工一館", latitude: 25.1502337, longitude: 121.7814742),
                DeliveryDestination(name: "沙灘排球場", latitude: 25.1309573, longitude: 121.5143297),
                DeliveryDestination(name: "造船系館", latitude: 25.0838499, longitude: 121.6620999),
                DeliveryDestination(name: "工學院", latitude: 25.0171933, longitude: 121.5425222),
                DeliveryDestination(name: "電機一館", latitude: 25.1505324, longitude: 121.7805505),
                DeliveryDestination(name: "電機二館", latitude: 25.0845996, longitude: 121.6612901),
                DeliveryDestination(name: "資工系館", latitude: 25.0840076, longitude: 121.6252481),
                DeliveryDestination(name: "水生動物實驗中心", latitude: 25.020006, longitude: 121.9880254),
                DeliveryDestination(name: "海洋生物培育館", latitude: 25.1512684, longitude: 121.7806267),
                DeliveryDestination(name: "聲學實驗中心", latitude: 25.1512003, longitude: 121.7809414),
                DeliveryDestination(name: "電資暨綜合教學大樓", latitude: 25.1507132, longitude: 121.7799803),
                DeliveryDestination(name: "大型空蝕水槽實驗室", latitude: 25.0837925, longitude: 121.6261048),
                DeliveryDestination(name: "河工二館", latitude: 25.1503729, longitude: 121.7792049)
            ]
        )
    ]

    static let defaultDestination: DeliveryDestination = demoCategories.first?.destinations.first ?? DeliveryDestination(name: "行政大樓", latitude: nil, longitude: nil)
}
