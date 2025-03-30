//
//  Models.swift
//  Chess
//
//  Created by Aren Koş on 31.03.2025.
//

import Foundation
import SwiftUI // Color için gerekli olabilir

// MARK: - Temel Veri Modelleri

enum PieceColor: String, CaseIterable, Identifiable {
    case white = "Beyaz"
    case black = "Siyah"

    var id: String { self.rawValue } // Identifiable için

    var opposite: PieceColor {
        return self == .white ? .black : .white
    }
}

enum PieceType: String {
    case king = "Şah"
    case queen = "Vezir"
    case rook = "Kale"
    case bishop = "Fil"
    case knight = "At"
    case pawn = "Piyon"

    // Notasyon için kısa harf (Piyon hariç)
    var notationLetter: String {
        switch self {
        case .king: return "Ş" // Veya "K" uluslararası için
        case .queen: return "V" // Veya "Q"
        case .rook: return "K" // Veya "R"
        case .bishop: return "F" // Veya "B"
        case .knight: return "A" // Veya "N"
        case .pawn: return ""    // Piyon için harf kullanılmaz
        }
    }

    func getSymbol(color: PieceColor) -> String {
        switch color {
        case .white:
            switch self {
            case .king: return "♔"
            case .queen: return "♕"
            case .rook: return "♖"
            case .bishop: return "♗"
            case .knight: return "♘"
            case .pawn: return "♙"
            }
        case .black:
            switch self {
            case .king: return "♚"
            case .queen: return "♛"
            case .rook: return "♜"
            case .bishop: return "♝"
            case .knight: return "♞"
            case .pawn: return "♟︎"
            }
        }
    }
}

struct ChessPiece: Identifiable, Equatable {
    let id = UUID()
    var type: PieceType      // 'var' yapıldı (önceki düzeltme)
    let color: PieceColor
    var position: BoardPosition
    var hasMoved: Bool = false

    static func == (lhs: ChessPiece, rhs: ChessPiece) -> Bool {
        lhs.id == rhs.id && lhs.position == rhs.position && lhs.hasMoved == rhs.hasMoved && lhs.type == rhs.type
    }
}

struct BoardPosition: Hashable, Equatable {
    var row: Int // 0'dan 7'ye (0 = Siyahın arka sırası, 7 = Beyazın arka sırası)
    var col: Int // 0'dan 7'ye (0 = a sütunu, 7 = h sütunu)

    var isValid: Bool {
        return row >= 0 && row < 8 && col >= 0 && col < 8
    }

    // Algebraic Notation (e.g., "a1", "h8")
    // Beyazın aşağıda olduğu standart görünüm varsayımıyla
    var algebraic: String {
        guard isValid else { return "??" }
        let file = String(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(col))!)
        let rank = String(8 - row) // 0. satır = 8. rank, 7. satır = 1. rank
        return "\(file)\(rank)"
    }

    static func - (lhs: BoardPosition, rhs: BoardPosition) -> (dr: Int, dc: Int) {
        return (lhs.row - rhs.row, lhs.col - rhs.col)
    }

    static func + (lhs: BoardPosition, rhs: (dr: Int, dc: Int)) -> BoardPosition {
        return BoardPosition(row: lhs.row + rhs.dr, col: lhs.col + rhs.dc)
    }
}

// Bir hamleyi temsil eder
struct Move: Hashable, Identifiable {
    let id = UUID()
    let piece: PieceType // Hamleyi yapan taşın türü (notasyon için)
    let color: PieceColor // Hamleyi yapanın rengi
    let from: BoardPosition
    let to: BoardPosition
    var capturedPieceType: PieceType? = nil // Yakalanan taşın türü (notasyon için)
    var isCastleKingside: Bool = false
    var isCastleQueenside: Bool = false
    var isEnPassantCapture: Bool = false
    var enPassantCapturedPawnPosition: BoardPosition? = nil // En passant'da yakalanan piyonun yeri
    var promotionType: PieceType? = nil
    var notation: String? = nil // Hesaplandıktan sonra buraya yazılacak
    var causesCheck: Bool = false
    var causesCheckmate: Bool = false
}

// Oyunun durumu
enum GameStatus {
    case setup // Ayarlar ekranı
    case ongoing
    case checkmate
    case stalemate
    case timeout
    case draw // Diğer berabere durumları eklenebilir
}

// Zaman Kontrolü Ayarları
struct TimeControl: Equatable, Hashable {
    var baseMinutes: Int
    var incrementSeconds: Int

    static let unlimited = TimeControl(baseMinutes: 0, incrementSeconds: 0) // Süresiz oyun
    static let standard = TimeControl(baseMinutes: 5, incrementSeconds: 3) // Örnek: 5+3

    var hasTimeLimit: Bool {
        baseMinutes > 0
    }
}

// Kullanıcı Ayarları
struct PlayerSettings {
    var playerColor: PieceColor = .white // Kullanıcının oynamak istediği renk (aşağıda olacak)
    var timeControl: TimeControl = .standard
    var isAgainstComputer: Bool = false // Bilgisayara karşı mı?
    var computerDifficulty: Int = 3 // Yapay zeka zorluk seviyesi (1-5 arası)
    // Gelecekte: Tahta / Taş teması vb.
}
