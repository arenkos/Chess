//
//  GameViewModel.swift
//  Chess
//
//  Created by Aren Koş on 31.03.2025.
//

import Foundation
import SwiftUI // Timer için Combine gerekebilir

class GameViewModel: ObservableObject {

    // MARK: - Published Properties (UI Güncellemeleri için)
    @Published var board: [[ChessPiece?]]
    @Published var selectedPiecePosition: BoardPosition? = nil
    @Published var possibleMoves: Set<Move> = []
    @Published var currentPlayer: PieceColor = .white
    @Published var gameStatus: GameStatus = .setup // Başlangıçta ayar ekranı
    @Published var statusMessage: String = "Ayarları Yapın"
    @Published var moveHistory: [Move] = []
    @Published var whiteTimeRemaining: TimeInterval = 0
    @Published var blackTimeRemaining: TimeInterval = 0
    @Published var lastMove: Move? = nil
    @Published var playerSettings: PlayerSettings = PlayerSettings() // Kullanıcı ayarları
    @Published var whiteKingInCheck: Bool = false // UI'da şah vurgusu için
    @Published var blackKingInCheck: Bool = false // UI'da şah vurgusu için
    @Published var isAgainstComputer: Bool = false // Bilgisayara karşı mı?
    @Published var computerDifficulty: Int = 3 // Yapay zeka zorluk derecesi (1-5)
    @Published var isBoardFlipped: Bool = false // Tahtanın çevrilip çevrilmediği

    // MARK: - Internal State
    private var whiteCanCastleKingside: Bool = true
    private var whiteCanCastleQueenside: Bool = true
    private var blackCanCastleKingside: Bool = true
    private var blackCanCastleQueenside: Bool = true
    private var enPassantTarget: BoardPosition? = nil
    private var gameTimer: Timer?
    public var activeTimerColor: PieceColor? = nil

    // MARK: - Initialization
    init() {
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        // Başlangıçta boş tahta, setup'tan sonra doldurulacak
    }

    // MARK: - Game Setup
    func startGame() {
        resetBoardAndState()
        setupInitialPieces()
        currentPlayer = .white // Beyaz başlar
        gameStatus = .ongoing
        moveHistory = []
        lastMove = nil
        
        // Zamanlayıcıları ayarla ve başlat (eğer zaman limiti varsa)
        if playerSettings.timeControl.hasTimeLimit {
            let startTime = TimeInterval(playerSettings.timeControl.baseMinutes * 60)
            whiteTimeRemaining = startTime
            blackTimeRemaining = startTime
            startTimer(for: .white) // Beyazın süresini başlat
        } else {
            // Süresiz oyun
            whiteTimeRemaining = 0
            blackTimeRemaining = 0
            stopTimer()
        }
        
        updateStatusMessage()
        updateCheckStatus() // Başlangıçta şah durumu kontrolü (normalde olmaz ama garanti)
        
        // Eğer bilgisayara karşı oynuyorsa ve bilgisayar beyazsa, bilgisayarın hamle yapmasını sağla
        if isAgainstComputer && playerSettings.playerColor == .black {
            makeComputerMove()
        }
    }

    func resetBoardAndState() {
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        whiteCanCastleKingside = true
        whiteCanCastleQueenside = true
        blackCanCastleKingside = true
        blackCanCastleQueenside = true
        enPassantTarget = nil
        selectedPiecePosition = nil
        possibleMoves = []
        stopTimer() // Önceki oyundan kalma timer'ı durdur
    }

    func setupInitialPieces() {
        let pieceTypes: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for (col, type) in pieceTypes.enumerated() {
            placePiece(ChessPiece(type: type, color: .black, position: BoardPosition(row: 0, col: col)))
            placePiece(ChessPiece(type: .pawn, color: .black, position: BoardPosition(row: 1, col: col)))
            placePiece(ChessPiece(type: .pawn, color: .white, position: BoardPosition(row: 6, col: col)))
            placePiece(ChessPiece(type: type, color: .white, position: BoardPosition(row: 7, col: col)))
        }
    }

    func placePiece(_ piece: ChessPiece?) {
        guard let piece = piece, piece.position.isValid else { return }
        board[piece.position.row][piece.position.col] = piece
    }
    
    // MARK: - User Interaction
    func squareTapped(position: BoardPosition) {
        guard gameStatus == .ongoing else { return }

        if let selectedPos = selectedPiecePosition {
            let potentialMove = possibleMoves.first { $0.to == position }
            if let move = potentialMove {
                makeMove(move) // Hamleyi yap
                selectedPiecePosition = nil
                possibleMoves = []
            } else {
                selectedPiecePosition = nil // Geçersiz hamle, seçimi kaldır
                possibleMoves = []
                if let piece = pieceAt(position), piece.color == currentPlayer {
                    selectedPiecePosition = position // Başka kendi taşına tıkladı, onu seç
                    generatePossibleMoves(for: piece)
                }
            }
        } else {
            if let piece = pieceAt(position), piece.color == currentPlayer {
                selectedPiecePosition = position // Yeni taş seçildi
                generatePossibleMoves(for: piece)
            }
        }
    }

    // MARK: - Move Execution
    func makeMove(_ rawMove: Move) {
        guard gameStatus == .ongoing, var pieceToMove = pieceAt(rawMove.from) else { return }

        // Bir sonraki hamle için en passant hedefini temizle (önceki değeri sakla)
        let previousEnPassantTarget = enPassantTarget
        enPassantTarget = nil

        // Hamleyi detaylandır (yakalanan taş vs.)
        var move = rawMove
        move.capturedPieceType = pieceAt(move.to)?.type // Normal yeme durumu
        
        // Eski pozisyonu temizle
        board[move.from.row][move.from.col] = nil

        // Özel Hamleler
        if move.isCastleKingside {
            pieceToMove.position = move.to; pieceToMove.hasMoved = true; placePiece(pieceToMove)
            let rookFrom = BoardPosition(row: move.from.row, col: 7)
            let rookTo = BoardPosition(row: move.from.row, col: 5)
            if var rook = pieceAt(rookFrom) { board[rookFrom.row][rookFrom.col] = nil; rook.position = rookTo; rook.hasMoved = true; placePiece(rook) }
        } else if move.isCastleQueenside {
            pieceToMove.position = move.to; pieceToMove.hasMoved = true; placePiece(pieceToMove)
            let rookFrom = BoardPosition(row: move.from.row, col: 0)
            let rookTo = BoardPosition(row: move.from.row, col: 3)
            if var rook = pieceAt(rookFrom) { board[rookFrom.row][rookFrom.col] = nil; rook.position = rookTo; rook.hasMoved = true; placePiece(rook) }
        } else if move.isEnPassantCapture {
            guard let capturedPawnPos = move.enPassantCapturedPawnPosition else { return }
             move.capturedPieceType = pieceAt(capturedPawnPos)?.type // Yakalanan piyonu kaydet
            board[capturedPawnPos.row][capturedPawnPos.col] = nil // Rakip piyonu kaldır
            pieceToMove.position = move.to; pieceToMove.hasMoved = true; placePiece(pieceToMove)
        } else {
            // Normal Hamle / Yakalama
            board[move.to.row][move.to.col] = nil // Hedefi temizle (yakalama için)
            pieceToMove.position = move.to
            pieceToMove.hasMoved = true

            // Piyon Terfisi
            if pieceToMove.type == .pawn && (move.to.row == 0 || move.to.row == 7) {
                 // Otomatik Vezir'e terfi (UI seçimi eklenebilir)
                pieceToMove.type = move.promotionType ?? .queen
                 move.promotionType = pieceToMove.type // Hamleye terfiyi kaydet
            }
            
            // Piyon 2 kare ileri gittiyse en passant hedefi ayarla
            if pieceToMove.type == .pawn && abs(move.to.row - move.from.row) == 2 {
                enPassantTarget = BoardPosition(row: (move.from.row + move.to.row) / 2, col: move.from.col)
            }

            placePiece(pieceToMove)
        }
        
        // Rok haklarını güncelle
        updateCastlingRights(movedPiece: pieceToMove, from: move.from, to: move.to)

        // Sıradaki oyuncu için Şah/Mat kontrolü yap ve hamleye ekle
        let opponentColor = currentPlayer.opposite
        let opponentInCheck = isKingInCheck(color: opponentColor) // Hamle *sonrası* rakibin durumu
        let opponentHasLegalMoves = !getAllLegalMoves(for: opponentColor).isEmpty

        move.causesCheck = opponentInCheck
        if opponentInCheck && !opponentHasLegalMoves {
            move.causesCheckmate = true
            gameStatus = .checkmate
        } else if !opponentInCheck && !opponentHasLegalMoves {
             gameStatus = .stalemate
        }

        // Notasyonu oluştur ve hamleye ekle
        move.notation = generateAlgebraicNotation(for: move)

        // Hamle Geçmişi
        moveHistory.append(move)
        lastMove = move // Son hamleyi güncelle

        // Sırayı Değiştir
        currentPlayer = opponentColor
        
        // Zamanlayıcıyı Değiştir
         if playerSettings.timeControl.hasTimeLimit {
             switchTimer()
         }

        // Oyun Durumu ve Mesajı Güncelle (Mat/Pat zaten yukarıda kontrol edildi)
        if gameStatus == .ongoing { // Eğer mat/pat olmadıysa durumu güncelle
             updateGameStatus() // 50 hamle kuralı vb. eklenebilir
        }
        updateStatusMessage()
        updateCheckStatus() // Yeni oyuncu için şah durumunu UI için güncelle

        // Oyun bittiyse zamanlayıcıyı durdur
        if gameStatus != .ongoing {
            stopTimer()
        } else if isAgainstComputer && currentPlayer != playerSettings.playerColor {
            // Eğer oyun devam ediyorsa ve sıra bilgisayardaysa, bilgisayar hamlesini yap
            makeComputerMove()
        }
    }

    // MARK: - Game Status & Rules
    
    // Mat/Pat kontrolü için ana fonksiyon (makeMove içinde çağrılır)
    func updateGameStatus() {
        // Eğer zaten mat/pat durumu ayarlandıysa dokunma
        guard gameStatus == .ongoing else { return }

        let legalMoves = getAllLegalMoves(for: currentPlayer)
        let kingInCheck = isKingInCheck(color: currentPlayer)

        if legalMoves.isEmpty {
            if kingInCheck {
                gameStatus = .checkmate
            } else {
                gameStatus = .stalemate
            }
        } else {
            gameStatus = .ongoing
        }
        // TODO: 50 hamle kuralı, yetersiz materyal gibi diğer berabere durumları eklenebilir
    }

    // Şah durumunu UI için günceller
    func updateCheckStatus() {
        whiteKingInCheck = isKingInCheck(color: .white)
        blackKingInCheck = isKingInCheck(color: .black)
    }

    func updateStatusMessage() {
        switch gameStatus {
        case .setup:
            statusMessage = "Ayarları Yapın ve Başlatın"
        case .ongoing:
            let checkString = isKingInCheck(color: currentPlayer) ? " (ŞAH!)" : ""
            statusMessage = "Sıra: \(currentPlayer.rawValue)\(checkString)"
        case .checkmate:
            statusMessage = "ŞAH MAT! \(currentPlayer.opposite.rawValue) kazandı."
            stopTimer()
        case .stalemate:
            statusMessage = "PAT! Oyun berabere."
            stopTimer()
        case .timeout:
            statusMessage = "SÜRE BİTTİ! \(currentPlayer.opposite.rawValue) kazandı."
            // stopTimer() zaten timeout içinde çağrılır
         case .draw:
             statusMessage = "Oyun berabere."
             stopTimer()
        }
    }

    // Belirli bir taş için olası hamleleri UI'da göstermek üzere hesaplar
    func generatePossibleMoves(for piece: ChessPiece) {
        guard piece.color == currentPlayer else {
            possibleMoves = []
            return
        }
        // Tüm yasal hamleleri al ve sadece bu taşa ait olanları filtrele
        possibleMoves = getAllLegalMoves(for: currentPlayer).filter { $0.from == piece.position }
    }

    // Bir oyuncu için TÜM yasal hamleleri üretir (Mat/Pat kontrolü için kritik)
    func getAllLegalMoves(for color: PieceColor) -> Set<Move> {
        var legalMoves: Set<Move> = []
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == color {
                    let pseudoLegalMoves = generatePseudoLegalMoves(for: piece)
                    for move in pseudoLegalMoves {
                        // Hamlenin yasal olup olmadığını (şah tehdidi yaratıp yaratmadığını) kontrol et
                        if isMoveTrulyLegal(move: move, color: color) {
                            legalMoves.insert(move)
                        }
                    }
                }
            }
        }
        return legalMoves
    }

    // Bir hamlenin gerçekten yasal olup olmadığını kontrol eder (şahı tehlikeye atmamalı)
    // Bu fonksiyon, hamleyi geçici olarak tahtada yapar ve sonucu kontrol eder.
    func isMoveTrulyLegal(move: Move, color: PieceColor) -> Bool {
        // 1. Tahtanın mevcut durumunu SAKLA
        let originalBoard = board
        let originalEnPassantTarget = enPassantTarget
        let originalCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)
        guard var tempPiece = pieceAt(move.from) else { return false } // Oynanacak taş olmalı
        let capturedPiece = pieceAt(move.to) // Hedefteki taş (varsa)

        // 2. Hamleyi Geçici Olarak Uygula (makeMove'un basitleştirilmiş hali)
        board[move.from.row][move.from.col] = nil // Eski yeri boşalt
        // Özel durumlar (En Passant yakalama)
        if move.isEnPassantCapture {
            guard let capturedPawnPos = move.enPassantCapturedPawnPosition else {
                // Hata durumu, tahtayı geri yükle ve false dön
                board = originalBoard
                enPassantTarget = originalEnPassantTarget
                 (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside) = originalCastlingRights
                return false
            }
             board[capturedPawnPos.row][capturedPawnPos.col] = nil // Yakalanan piyonu kaldır
        }
        // Rok için özel simülasyon GEREKMEZ, çünkü isKingInCheck zaten
        // rok yolunun tehdit altında olup olmadığını kontrol eder. Sadece Şah'ı hareket ettir.
        tempPiece.position = move.to
         board[move.to.row][move.to.col] = tempPiece // Taşı yeni yerine koy


        // 3. Hamle Sonrası Şah Durumunu Kontrol Et
        let isKingSafe = !isKingInCheck(color: color) // Kendi şahımız güvende mi?

        // 4. Tahtayı Orijinal Durumuna GERİ YÜKLE
        board = originalBoard
        enPassantTarget = originalEnPassantTarget
        (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside) = originalCastlingRights

        // 5. Sonucu Döndür
        return isKingSafe
    }


    // Belirli bir kare rakip tarafından tehdit ediliyor mu?
    // skipKingSafety: Şahın güvenli karelere gidip gidemeyeceğini atla (sonsuz döngü engellemek için)
    func isSquareAttacked(position: BoardPosition, by attackerColor: PieceColor, skipKingSafety: Bool = false) -> Bool {
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == attackerColor {
                    let pseudoLegalMoves = generatePseudoLegalMoves(for: piece, attackCheckOnly: true, skipKingSafety: skipKingSafety)
                    if pseudoLegalMoves.contains(where: { $0.to == position }) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // Şah tehdit altında mı?
    func isKingInCheck(color: PieceColor) -> Bool {
        guard let kingPosition = findKingPosition(for: color) else { return false }
        return isSquareAttacked(position: kingPosition, by: color.opposite, skipKingSafety: true)
    }

    // Belirli bir renkteki şahın pozisyonunu bulur
    func findKingPosition(for color: PieceColor) -> BoardPosition? {
        board.joined().first(where: { $0?.type == .king && $0?.color == color })??.position
    }

    // Belirli bir pozisyondaki taşı döndürür
    func pieceAt(_ position: BoardPosition) -> ChessPiece? {
        guard position.isValid else { return nil }
        return board[position.row][position.col]
    }
    
    // Rok haklarını günceller
    func updateCastlingRights(movedPiece: ChessPiece, from: BoardPosition, to: BoardPosition) {
        // Şah hareketi tüm rok haklarını bozar
        if movedPiece.type == .king {
            if movedPiece.color == .white {
                whiteCanCastleKingside = false
                whiteCanCastleQueenside = false
            } else {
                blackCanCastleKingside = false
                blackCanCastleQueenside = false
            }
        }
        // Kale hareketi ilgili tarafın rok hakkını bozar
        if movedPiece.type == .rook {
             if movedPiece.color == .white {
                 if from.col == 0 && from.row == 7 { whiteCanCastleQueenside = false }
                 if from.col == 7 && from.row == 7 { whiteCanCastleKingside = false }
             } else { // Siyah Kale
                 if from.col == 0 && from.row == 0 { blackCanCastleQueenside = false }
                 if from.col == 7 && from.row == 0 { blackCanCastleKingside = false }
             }
        }
        
        // Rakip kalenin yakalanması da rok hakkını bozar
        let whiteQRookPos = BoardPosition(row: 7, col: 0)
        let whiteKRookPos = BoardPosition(row: 7, col: 7)
        let blackQRookPos = BoardPosition(row: 0, col: 0)
        let blackKRookPos = BoardPosition(row: 0, col: 7)

        if to == whiteQRookPos { whiteCanCastleQueenside = false }
        if to == whiteKRookPos { whiteCanCastleKingside = false }
        if to == blackQRookPos { blackCanCastleQueenside = false }
        if to == blackKRookPos { blackCanCastleKingside = false }
    }

    // MARK: - Move Generation (Pseudo & Notation)

    // Bir taş için (şah kontrolü yapmadan) olası tüm hamleleri üretir
    // attackCheckOnly: Sadece tehdit kontrolü için mi? (Piyonun sadece yeme hamlelerini üretir)
    func generatePseudoLegalMoves(for piece: ChessPiece, attackCheckOnly: Bool = false, skipKingSafety: Bool = false) -> Set<Move> {
        var moves: Set<Move> = []
        let pos = piece.position
        let color = piece.color

        switch piece.type {
        case .pawn:
            let direction = (color == .white) ? -1 : 1
            let startRow = (color == .white) ? 6 : 1
            let promotionRow = (color == .white) ? 0 : 7

            // 1. Tek kare ileri
            let oneStep = pos + (dr: direction, dc: 0)
            if oneStep.isValid && pieceAt(oneStep) == nil && !attackCheckOnly {
                if oneStep.row == promotionRow {
                     [.queen, .rook, .bishop, .knight].forEach { type in // Terfi seçenekleri
                         moves.insert(Move(piece: .pawn, color: color, from: pos, to: oneStep, promotionType: type))
                     }
                } else {
                    moves.insert(Move(piece: .pawn, color: color, from: pos, to: oneStep))
                }
                 // 2. İki kare ileri (başlangıçta ve önü boşsa)
                if pos.row == startRow {
                    let twoSteps = pos + (dr: 2 * direction, dc: 0)
                    if twoSteps.isValid && pieceAt(twoSteps) == nil {
                         moves.insert(Move(piece: .pawn, color: color, from: pos, to: twoSteps))
                    }
                }
            }
            // 3. Çapraz Yeme & En Passant
            for dc in [-1, 1] {
                let capturePos = pos + (dr: direction, dc: dc)
                if capturePos.isValid {
                    // Normal Çapraz Yeme
                    if let targetPiece = pieceAt(capturePos), targetPiece.color != color {
                        if capturePos.row == promotionRow && !attackCheckOnly {
                             [.queen, .rook, .bishop, .knight].forEach { type in // Terfi ile yeme
                                 moves.insert(Move(piece: .pawn, color: color, from: pos, to: capturePos, capturedPieceType: targetPiece.type, promotionType: type))
                             }
                        } else {
                            moves.insert(Move(piece: .pawn, color: color, from: pos, to: capturePos, capturedPieceType: targetPiece.type))
                        }
                    }
                    // En Passant (Geçerken Alma)
                    else if capturePos == enPassantTarget && !attackCheckOnly {
                        let capturedPawnPos = BoardPosition(row: pos.row, col: capturePos.col) // Yakalanan piyonun *asıl* yeri
                         if let capturedPawn = pieceAt(capturedPawnPos), capturedPawn.type == .pawn, capturedPawn.color != color {
                              moves.insert(Move(piece: .pawn, color: color, from: pos, to: capturePos, capturedPieceType: .pawn, isEnPassantCapture: true, enPassantCapturedPawnPosition: capturedPawnPos))
                         }
                    }
                }
            }
        case .knight:
            let offsets: [(dr: Int, dc: Int)] = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)]
            for offset in offsets {
                let targetPos = pos + offset
                if targetPos.isValid {
                    let targetPiece = pieceAt(targetPos)
                    if targetPiece == nil || targetPiece!.color != color { // Boş veya rakip
                        moves.insert(Move(piece: .knight, color: color, from: pos, to: targetPos, capturedPieceType: targetPiece?.type))
                    }
                }
            }
        case .bishop, .rook, .queen:
             var directions: [(dr: Int, dc: Int)] = []
             if piece.type != .rook { directions += [(-1,-1),(-1,1),(1,-1),(1,1)] } // Fil ve Vezir
             if piece.type != .bishop { directions += [(-1,0),(1,0),(0,-1),(0,1)] } // Kale ve Vezir

            for dir in directions {
                var currentPos = pos + dir
                while currentPos.isValid {
                    let targetPiece = pieceAt(currentPos)
                    if targetPiece == nil { // Boş kare
                        moves.insert(Move(piece: piece.type, color: color, from: pos, to: currentPos))
                    } else {
                        if targetPiece!.color != color { // Rakip taşı yeme
                             moves.insert(Move(piece: piece.type, color: color, from: pos, to: currentPos, capturedPieceType: targetPiece?.type))
                        }
                        break // Kendi veya rakip taşına ulaştı, bu yönde devam etme
                    }
                    currentPos = currentPos + dir
                }
            }
        case .king:
            // Normal 1 kare hareketler
             let offsets: [(dr: Int, dc: Int)] = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
            for offset in offsets {
                let targetPos = pos + offset
                if targetPos.isValid {
                     let targetPiece = pieceAt(targetPos)
                    // ÖNEMLİ: Şah, tehdit altındaki karelere gidemez (pseudo-legal aşamasında kontrol)
                     if skipKingSafety || !isSquareAttacked(position: targetPos, by: color.opposite, skipKingSafety: true) {
                         if targetPiece == nil || targetPiece!.color != color {
                             moves.insert(Move(piece: .king, color: color, from: pos, to: targetPos, capturedPieceType: targetPiece?.type))
                         }
                     }
                }
            }
            // Rok (Castling)
            if !piece.hasMoved && !attackCheckOnly && (skipKingSafety || !isKingInCheck(color: color)) { // Şah oynamadıysa ve ŞAH altında DEĞİLSE
                let row = pos.row
                // Kısa Rok (Şah tarafı)
                let kRookPos = BoardPosition(row: row, col: 7)
                let kCastlePossible = (color == .white) ? whiteCanCastleKingside : blackCanCastleKingside
                if kCastlePossible, let kRook = pieceAt(kRookPos), kRook.type == .rook, !kRook.hasMoved,
                   pieceAt(pos+(dr:0, dc:1)) == nil, pieceAt(pos+(dr:0, dc:2)) == nil,
                   (skipKingSafety || !isSquareAttacked(position: pos+(dr:0, dc:1), by: color.opposite, skipKingSafety: true)),
                   (skipKingSafety || !isSquareAttacked(position: pos+(dr:0, dc:2), by: color.opposite, skipKingSafety: true)) {
                    moves.insert(Move(piece: .king, color: color, from: pos, to: pos+(dr:0, dc:2), isCastleKingside: true))
                }
                // Uzun Rok (Vezir tarafı)
                 let qRookPos = BoardPosition(row: row, col: 0)
                 let qCastlePossible = (color == .white) ? whiteCanCastleQueenside : blackCanCastleQueenside
                 if qCastlePossible, let qRook = pieceAt(qRookPos), qRook.type == .rook, !qRook.hasMoved,
                    pieceAt(pos+(dr:0, dc:-1)) == nil, pieceAt(pos+(dr:0, dc:-2)) == nil, pieceAt(pos+(dr:0, dc:-3)) == nil,
                    (skipKingSafety || !isSquareAttacked(position: pos+(dr:0, dc:-1), by: color.opposite, skipKingSafety: true)), // Şahın geçtiği kareler
                    (skipKingSafety || !isSquareAttacked(position: pos+(dr:0, dc:-2), by: color.opposite, skipKingSafety: true)) { // Şahın vardığı kare
                     moves.insert(Move(piece: .king, color: color, from: pos, to: pos+(dr:0, dc:-2), isCastleQueenside: true))
                 }
            }
        }
        return moves
    }
    
    // Basitleştirilmiş algebraik notasyon üretir
    func generateAlgebraicNotation(for move: Move) -> String {
        if move.isCastleKingside { return "O-O" }
        if move.isCastleQueenside { return "O-O-O" }

        var notation = ""

        // Piyon dışındaki taşlar için baş harf
        notation += move.piece.notationLetter

        // TODO: Aynı türden birden fazla taş aynı kareye gidebiliyorsa
        // kaynak kare belirtilmeli (örn: Nga5, Rdf8). Bu kısım şimdilik atlandı.
        // let ambiguity = resolveAmbiguity(for: move)
        // notation += ambiguity

        // Yakalama durumu
        if move.capturedPieceType != nil {
             // Piyon yakalamasında kaynak sütun eklenir (örn: exd5)
            if move.piece == .pawn {
                notation += String(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(move.from.col))!)
            }
            notation += "x"
        }

        // Hedef kare
        notation += move.to.algebraic

        // Piyon Terfisi
        if let promotion = move.promotionType {
            notation += "=" + promotion.notationLetter
        }

        // Şah / Mat Durumu
        if move.causesCheckmate {
            notation += "#"
        } else if move.causesCheck {
            notation += "+"
        }

        return notation
    }


    // MARK: - Timer Logic
    func startTimer(for color: PieceColor) {
        stopTimer() // Önce varsa eskiyi durdur
        guard playerSettings.timeControl.hasTimeLimit else { return } // Süre limiti yoksa başlatma

        activeTimerColor = color
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.gameStatus == .ongoing else {
                self?.stopTimer()
                return
            }

            if self.activeTimerColor == .white {
                self.whiteTimeRemaining -= 0.1
                if self.whiteTimeRemaining <= 0 {
                    self.handleTimeout(loser: .white)
                }
            } else {
                self.blackTimeRemaining -= 0.1
                 if self.blackTimeRemaining <= 0 {
                    self.handleTimeout(loser: .black)
                }
            }
             // Zamanı formatlayıp UI'a yansıtmak için @Published değişkenleri tetikle
             objectWillChange.send()
        }
    }

    func stopTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
        activeTimerColor = nil
    }

    func switchTimer() {
        guard playerSettings.timeControl.hasTimeLimit else { return }
        guard let previousPlayer = activeTimerColor else {
             // İlk hamle durumu, beyaz için başlat
             startTimer(for: .white)
             return
        }

        // Hamle yapan oyuncuya increment ekle
        let increment = TimeInterval(playerSettings.timeControl.incrementSeconds)
        if previousPlayer == .white {
            whiteTimeRemaining += increment
        } else {
            blackTimeRemaining += increment
        }
        
        // Zamanlayıcıyı diğer oyuncu için başlat
        startTimer(for: previousPlayer.opposite)
        
         // Zamanı formatlayıp UI'a yansıtmak için @Published değişkenleri tetikle
         objectWillChange.send()
    }

    func handleTimeout(loser: PieceColor) {
        stopTimer()
        gameStatus = .timeout
        currentPlayer = loser // Kaybeden oyuncu olarak ayarla (statusMessage'da kullanmak için)
        updateStatusMessage()
    }

    // Zamanı MM:SS.s formatında gösterir
     func formatTime(_ time: TimeInterval) -> String {
         if !playerSettings.timeControl.hasTimeLimit { return "--:--" } // Süresiz oyun
         let totalSeconds = Int(max(0, time))
         let minutes = totalSeconds / 60
         let seconds = totalSeconds % 60
         // let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10) // Saniyenin onda biri
         // return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
         return String(format: "%02d:%02d", minutes, seconds) // Sadece dakika:saniye
     }
     
    // MARK: - AI Logic
    // Yapay zeka için sıranın bilgisayara geldiğinde hamle yapma
    func makeComputerMove() {
        guard isAgainstComputer && currentPlayer != playerSettings.playerColor && gameStatus == .ongoing else { return }
        
        // Bilgisayarın kısa bir düşünme süresi olsun (zorluk seviyesine bağlı)
        let thinkingTime = Double(computerDifficulty) * 0.35 // Zorluk arttıkça daha uzun düşünecek
        
        // Bilgisayar düşünüyor...
        DispatchQueue.main.asyncAfter(deadline: .now() + thinkingTime) { [weak self] in
            guard let self = self, self.gameStatus == .ongoing else { return }
            
            if let computerMove = self.calculateBestComputerMove() {
                self.makeMove(computerMove)
            }
        }
    }
    
    // Yapay zekanın hamle seçimi (zorluk seviyesine göre)
    private func calculateBestComputerMove() -> Move? {
        let computerColor = playerSettings.playerColor.opposite
        var legalMoves = getAllLegalMoves(for: computerColor)
        
        guard !legalMoves.isEmpty else { return nil }
        
        // Zorluk seviyesi 1: Tamamen rastgele hamle yap
        if computerDifficulty == 1 {
            return legalMoves.randomElement()
        }
        
        // Taşların değerleri - şaha yüksek değer vererek onu korumayı önceliklendir
        let pieceValues: [PieceType: Int] = [
            .pawn: 1,
            .knight: 3,
            .bishop: 3,
            .rook: 5,
            .queen: 9,
            .king: 100 // Şahı korumak için çok yüksek değer
        ]
        
        // Mat yapıcı hamleleri her seviyede kontrol et (ama düşük seviyede gözden kaçır)
        let mateInOneMoves = legalMoves.filter { move in
            // Hamleyi simüle et
            let originalBoard = board
            let originalEnPassantTarget = enPassantTarget
            let originalCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)
            
            // Geçici olarak hamleyi uygula
            let capturedPiece = pieceAt(move.to)
            var tempPiece = pieceAt(move.from)!
            board[move.from.row][move.from.col] = nil
            
            if move.isEnPassantCapture, let capturedPawnPos = move.enPassantCapturedPawnPosition {
                board[capturedPawnPos.row][capturedPawnPos.col] = nil
            }
            
            tempPiece.position = move.to
            board[move.to.row][move.to.col] = tempPiece
            
            // Hamle sonrası mat kontrolü
            let opponentLegalMoves = getAllLegalMoves(for: playerSettings.playerColor)
            let opponentInCheck = isKingInCheck(color: playerSettings.playerColor)
            let causesCheckmate = opponentInCheck && opponentLegalMoves.isEmpty
            
            // Tahtayı geri al
            board = originalBoard
            enPassantTarget = originalEnPassantTarget
            (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside) = originalCastlingRights
            
            return causesCheckmate
        }
        
        // Her zorluk seviyesinde mat hamlelerini görme olasılığı
        if !mateInOneMoves.isEmpty {
            let chanceToSeemate: Double
            switch computerDifficulty {
            case 1: chanceToSeemate = 0.10 // Seviye 1: %10
            case 2: chanceToSeemate = 0.50 // Seviye 2: %50
            case 3: chanceToSeemate = 0.75 // Seviye 3: %75
            case 4: chanceToSeemate = 0.95 // Seviye 4: %95
            case 5: chanceToSeemate = 1.00 // Seviye 5: %100
            default: chanceToSeemate = 0.50
            }
            
            if Double.random(in: 0...1) < chanceToSeemate {
                return mateInOneMoves.randomElement()
            }
        }
        
        // Açılış kütüphanesi (Seviye 4-5)
        if moveHistory.count < 10 && computerDifficulty >= 4 {
            // e4, d4 merkez açılışlara öncelik ver
            if moveHistory.isEmpty && computerColor == .white {
                // İlk hamle için e4 veya d4 tercih et
                let goodFirstMoves = legalMoves.filter { 
                    let to = $0.to
                    return (to.row == 4 && (to.col == 3 || to.col == 4)) && pieceAt($0.from)?.type == .pawn
                }
                
                if !goodFirstMoves.isEmpty && Double.random(in: 0...1) > 0.1 {
                    return goodFirstMoves.randomElement()
                }
            }
            
            // Gelişim hamleleri - atlar, filler, rok
            let developmentMoves = legalMoves.filter { move in
                let piece = pieceAt(move.from)!
                
                // Şahın güvenliği için rok yapmaya çalış
                if piece.type == .king && (move.isCastleKingside || move.isCastleQueenside) {
                    return true
                }
                
                // Gelişim hamlelerini tercih et (atlar, filler dışarı çıksın)
                if (piece.type == .knight || piece.type == .bishop) && 
                   ((computerColor == .white && move.from.row == 7) || 
                    (computerColor == .black && move.from.row == 0)) {
                    return true
                }
                
                // Merkez piyonları ilerlet
                if piece.type == .pawn && 
                   ((computerColor == .white && move.from.row == 6 && (move.from.col == 3 || move.from.col == 4)) || 
                    (computerColor == .black && move.from.row == 1 && (move.from.col == 3 || move.from.col == 4))) {
                    return true
                }
                
                return false
            }
            
            if !developmentMoves.isEmpty {
                let openingChance: Double = (computerDifficulty == 5) ? 0.9 : 0.7
                if Double.random(in: 0...1) < openingChance {
                    return developmentMoves.randomElement()
                }
            }
        }
        
        // Şahı koruyan özel hamleler (tüm zorluk seviyeleri)
        let kingPosition = findKingPosition(for: computerColor)!
        let isKingChecked = isKingInCheck(color: computerColor)
        
        // Eğer şah tehdidi varsa, bunu öncelikle çöz
        if isKingChecked {
            let checkDefenseMoves = legalMoves.filter { move in
                // Hamleyi simüle et
                let originalBoard = board
                let originalEnPassantTarget = enPassantTarget
                let originalCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)
                
                var tempPiece = pieceAt(move.from)!
                board[move.from.row][move.from.col] = nil
                
                if move.isEnPassantCapture, let capturedPawnPos = move.enPassantCapturedPawnPosition {
                    board[capturedPawnPos.row][capturedPawnPos.col] = nil
                }
                
                tempPiece.position = move.to
                board[move.to.row][move.to.col] = tempPiece
                
                // Şah hala tehdit altında mı?
                let stillInCheck = isKingInCheck(color: computerColor)
                
                // Tahtayı geri al
                board = originalBoard
                enPassantTarget = originalEnPassantTarget
                (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside) = originalCastlingRights
                
                return !stillInCheck
            }
            
            if !checkDefenseMoves.isEmpty {
                // Seviye 5'te şahı mutlaka korur, diğer seviyelerde belli bir olasılık
                let chanceToDefend: Double
                switch computerDifficulty {
                case 1: chanceToDefend = 0.3
                case 2: chanceToDefend = 0.5
                case 3: chanceToDefend = 0.8
                case 4: chanceToDefend = 0.95
                case 5: chanceToDefend = 1.0
                default: chanceToDefend = 0.7
                }
                
                if Double.random(in: 0...1) < chanceToDefend {
                    // En iyi savunma hamlesini seç - mümkünse tehdit eden taşı yakala
                    let attackersPosition = findAttackingPieces(for: kingPosition, attackerColor: playerSettings.playerColor).map { $0.position }
                    
                    let captureAttackerMoves = checkDefenseMoves.filter { move in
                        return attackersPosition.contains(move.to)
                    }
                    
                    if !captureAttackerMoves.isEmpty && Double.random(in: 0...1) > 0.2 {
                        return captureAttackerMoves.randomElement()
                    }
                    
                    return checkDefenseMoves.randomElement()
                }
            }
        }
        
        // Taş değerlerine göre hamleleri değerlendir (zorluk 3+)
        if computerDifficulty >= 3 {
            // Yakalama hamlelerini değerlendir ve en değerli olanları bul
            var capturesByValue: [Int: [Move]] = [:]
            for move in legalMoves.filter({ $0.capturedPieceType != nil }) {
                if let capturedType = move.capturedPieceType, let value = pieceValues[capturedType] {
                    let movingPieceValue = pieceValues[pieceAt(move.from)!.type] ?? 1
                    
                    // Eğer değerli bir taşla, daha az değerli bir taş yakalanıyorsa değeri düşür
                    // Örneğin vezir ile piyon yakalamak yerine, at ile piyon yakalamayı tercih et
                    let captureValue = value - (movingPieceValue / 20)
                    
                    if capturesByValue[captureValue] == nil {
                        capturesByValue[captureValue] = []
                    }
                    capturesByValue[captureValue]?.append(move)
                }
            }
            
            // En değerli yakalama hamlelerini bul
            if !capturesByValue.isEmpty {
                let bestCaptureValue = capturesByValue.keys.max() ?? 0
                let bestCaptureMoves = capturesByValue[bestCaptureValue] ?? []
                
                if !bestCaptureMoves.isEmpty {
                    let captureChance: Double
                    switch computerDifficulty {
                    case 3: captureChance = 0.7
                    case 4: captureChance = 0.85
                    case 5: captureChance = 0.95
                    default: captureChance = 0.6
                    }
                    
                    if Double.random(in: 0...1) < captureChance {
                        return bestCaptureMoves.randomElement()
                    }
                }
            }
        }
        
        // Tehdit altındaki taşları korumaya çalış (zorluk 3+)
        if computerDifficulty >= 3 {
            // Tehdit altındaki değerli taşları bul
            var threatenedPieces: [(piece: ChessPiece, value: Int)] = []
            
            // Tüm bilgisayar taşlarını kontrol et
            for r in 0..<8 {
                for c in 0..<8 {
                    if let piece = board[r][c], piece.color == computerColor, piece.type != .king {
                        let position = BoardPosition(row: r, col: c)
                        if isSquareAttacked(position: position, by: playerSettings.playerColor) {
                            if let value = pieceValues[piece.type] {
                                threatenedPieces.append((piece, value))
                            }
                        }
                    }
                }
            }
            
            // Değerli taşları yüksek değerden düşük değere doğru sırala
            threatenedPieces.sort { $0.value > $1.value }
            
            // En değerli tehdit altındaki taşı koru
            if !threatenedPieces.isEmpty {
                let mostValuableThreatened = threatenedPieces.first!
                
                // Bu taşı kurtarmak için hamleler
                let saveMoves = legalMoves.filter { move in
                    return move.from == mostValuableThreatened.piece.position
                }
                
                if !saveMoves.isEmpty {
                    let saveChance: Double
                    switch computerDifficulty {
                    case 3: saveChance = 0.6
                    case 4: saveChance = 0.8
                    case 5: saveChance = 0.95
                    default: saveChance = 0.5
                    }
                    
                    if Double.random(in: 0...1) < saveChance {
                        // En güvenli kareye kaç
                        return saveMoves.randomElement()
                    }
                }
            }
        }
        
        // Şah çekme hamleleri (zorluk 3+)
        if computerDifficulty >= 3 {
            let checkMoves = legalMoves.filter { move in
                // Hamleyi simüle et
                let originalBoard = board
                
                var tempPiece = pieceAt(move.from)!
                board[move.from.row][move.from.col] = nil
                tempPiece.position = move.to
                board[move.to.row][move.to.col] = tempPiece
                
                let isCheck = isKingInCheck(color: playerSettings.playerColor)
                
                // Tahtayı geri al
                board = originalBoard
                
                return isCheck
            }
            
            if !checkMoves.isEmpty {
                let checkChance: Double
                switch computerDifficulty {
                case 3: checkChance = 0.6
                case 4: checkChance = 0.8
                case 5: checkChance = 0.9
                default: checkChance = 0.5
                }
                
                if Double.random(in: 0...1) < checkChance {
                    return checkMoves.randomElement()
                }
            }
        }
        
        // Merkez kontrolü (zorluk 2+)
        if computerDifficulty >= 2 {
            // Merkez kareleri (e4, d4, e5, d5)
            let centerSquares = [
                BoardPosition(row: 3, col: 3), BoardPosition(row: 3, col: 4),
                BoardPosition(row: 4, col: 3), BoardPosition(row: 4, col: 4)
            ]
            
            // Merkezi kontrol eden hamleler
            let centerControlMoves = legalMoves.filter { move in
                // Taş merkeze mi gidiyor? 
                if centerSquares.contains(move.to) {
                    return true
                }
                
                // Ya da taş merkezi etkiliyor mu? (Örn: fil/kale/vezir merkezi hedef alıyor)
                if let piece = pieceAt(move.from), piece.type == .bishop || piece.type == .rook || piece.type == .queen {
                    // Hamle sonrası bu taş merkezi tehdit ediyor mu?
                    let originalBoard = board
                    
                    board[move.from.row][move.from.col] = nil
                    var tempPiece = piece
                    tempPiece.position = move.to
                    board[move.to.row][move.to.col] = tempPiece
                    
                    let controlsCenter = centerSquares.contains { centerPos in
                        let pseudoMoves = generatePseudoLegalMoves(for: tempPiece, attackCheckOnly: true)
                        return pseudoMoves.contains { $0.to == centerPos }
                    }
                    
                    // Tahtayı geri al
                    board = originalBoard
                    
                    return controlsCenter
                }
                
                return false
            }
            
            if !centerControlMoves.isEmpty {
                let centerChance: Double
                switch computerDifficulty {
                case 2: centerChance = 0.4
                case 3: centerChance = 0.6
                case 4: centerChance = 0.7
                case 5: centerChance = 0.85
                default: centerChance = 0.4
                }
                
                if Double.random(in: 0...1) < centerChance {
                    return centerControlMoves.randomElement()
                }
            }
        }
        
        // Piyon terfisi hamleleri (her seviye)
        let promotionMoves = legalMoves.filter { $0.promotionType != nil }
        if !promotionMoves.isEmpty {
            let promotionChance = min(0.4 + (Double(computerDifficulty) * 0.15), 1.0)
            if Double.random(in: 0...1) < promotionChance {
                return promotionMoves.randomElement()
            }
        }
        
        // Seviye 5 için: Güvenlik değerlendirmesi ve gelecekteki tehlikeleri analiz et
        if computerDifficulty == 5 {
            // Son çare stratejik hamleler
            let strategicMoves = legalMoves.filter { move in
                // Hamleyi simüle et
                let originalBoard = board
                let originalEnPassantTarget = enPassantTarget
                
                var tempPiece = pieceAt(move.from)!
                board[move.from.row][move.from.col] = nil
                
                if move.isEnPassantCapture, let capturedPawnPos = move.enPassantCapturedPawnPosition {
                    board[capturedPawnPos.row][capturedPawnPos.col] = nil
                }
                
                tempPiece.position = move.to
                board[move.to.row][move.to.col] = tempPiece
                
                // Hamle sonrası değerlendirme
                
                // 1. Merkez kontrolü artıyor mu?
                let centerSquares = [
                    BoardPosition(row: 3, col: 3), BoardPosition(row: 3, col: 4),
                    BoardPosition(row: 4, col: 3), BoardPosition(row: 4, col: 4)
                ]
                let controlsCenter = centerSquares.contains { pos in
                    isSquareAttacked(position: pos, by: computerColor)
                }
                
                // 2. Şah için daha fazla hücre açılıyor mu?
                let kingPos = findKingPosition(for: computerColor)!
                let kingMobility = generatePseudoLegalMoves(for: ChessPiece(type: .king, color: computerColor, position: kingPos)).count
                
                // 3. Taşlar güvenli pozisyonda mı?
                let isPositionSafe = !isSquareAttacked(position: move.to, by: playerSettings.playerColor)
                
                // Tahtayı geri al
                board = originalBoard
                enPassantTarget = originalEnPassantTarget
                
                // Genel stratejik değerlendirme
                return controlsCenter || kingMobility >= 3 || isPositionSafe
            }
            
            if !strategicMoves.isEmpty {
                return strategicMoves.randomElement()
            }
        }
        
        // Hala bir hamle seçilmediyse, tüm hamleler içinden rastgele seç
        return legalMoves.randomElement()
    }
    
    // Belirli bir kareyi tehdit eden taşları bul (yapay zeka için yardımcı fonksiyon)
    private func findAttackingPieces(for position: BoardPosition, attackerColor: PieceColor) -> [ChessPiece] {
        var attackers: [ChessPiece] = []
        
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == attackerColor {
                    let moves = generatePseudoLegalMoves(for: piece, attackCheckOnly: true)
                    if moves.contains(where: { $0.to == position }) {
                        attackers.append(piece)
                    }
                }
            }
        }
        
        return attackers
    }
    
    // Bilgisayar için otomatik hamle kontrolü
    func checkAndMakeComputerMoveIfNeeded() {
        if isAgainstComputer && currentPlayer != playerSettings.playerColor {
            makeComputerMove()
        }
    }

    // Oyun modunu ayarla
    func setGameMode(againstComputer: Bool, difficulty: Int = 3) {
        isAgainstComputer = againstComputer
        computerDifficulty = max(1, min(5, difficulty)) // 1-5 aralığında sınırla
        
        // Eğer rakibe karşıysa ve oyuncu siyah seçtiyse tahtayı çevir
        isBoardFlipped = !againstComputer && playerSettings.playerColor == .black
    }
}
