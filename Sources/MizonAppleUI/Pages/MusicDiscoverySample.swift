import Foundation

struct MusicDiscoverySample: Identifiable {
    let title: String
    let persianTitle: String
    let artist: String
    let genre: String
    let persianGenre: String
    let image: String
    let duration: Int
    let likes: Int

    var id: String { image }

    static let all: [Self] = [
        .init(title: "Midnight Drive", persianTitle: "مسیر نیمه‌شب", artist: "آرمان راد",
              genre: "Pop", persianGenre: "پاپ", image: "midnight-drive", duration: 224, likes: 12840),
        .init(title: "After the Rain", persianTitle: "بعد از باران", artist: "رها مهر",
              genre: "Pop", persianGenre: "پاپ", image: "after-the-rain", duration: 198, likes: 8940),
        .init(title: "Blue Hour", persianTitle: "ساعت آبی", artist: "ماهان نوری",
              genre: "Electronic", persianGenre: "الکترونیک", image: "blue-hour", duration: 256, likes: 19320),
        .init(title: "Somewhere New", persianTitle: "یک جای تازه", artist: "آوا پارسا",
              genre: "Rock", persianGenre: "راک", image: "somewhere-new", duration: 213, likes: 6700),
        .init(title: "Quiet Room", persianTitle: "اتاق آرام", artist: "نوید راد",
              genre: "Ambient", persianGenre: "امبینت", image: "quiet-room", duration: 282, likes: 4680),
        .init(title: "Golden Days", persianTitle: "روزهای طلایی", artist: "نیما مهر",
              genre: "Pop", persianGenre: "پاپ", image: "golden-days", duration: 242, likes: 24650),
        .init(title: "City Lights", persianTitle: "چراغ‌های شهر", artist: "آرمان راد",
              genre: "Electronic", persianGenre: "الکترونیک", image: "city-lights", duration: 208, likes: 11240),
        .init(title: "Velvet Sky", persianTitle: "آسمان مخملی", artist: "رها مهر",
              genre: "Jazz", persianGenre: "جاز", image: "velvet-sky", duration: 267, likes: 7320),
        .init(title: "Slow Motion", persianTitle: "آهسته‌تر", artist: "ماهان نوری",
              genre: "Hip-Hop", persianGenre: "هیپ‌هاپ", image: "slow-motion", duration: 187, likes: 15760),
        .init(title: "Stay Awhile", persianTitle: "کمی بمان", artist: "آوا پارسا",
              genre: "Rock", persianGenre: "راک", image: "stay-awhile", duration: 231, likes: 9840),
        .init(title: "Ocean Air", persianTitle: "هوای دریا", artist: "نوید راد",
              genre: "Ambient", persianGenre: "امبینت", image: "ocean-air", duration: 304, likes: 5280),
        .init(title: "First Light", persianTitle: "اولین روشنایی", artist: "نیما مهر",
              genre: "Jazz", persianGenre: "جاز", image: "first-light", duration: 219, likes: 3760),
    ]
}
