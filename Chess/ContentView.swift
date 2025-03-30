/*
import SwiftUI

// MARK: - Veri Modelleri

enum PieceColor: String, CaseIterable {
    case white = "Beyaz"
    case black = "Siyah"

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
    var type: PieceType
    let color: PieceColor
    var position: BoardPosition
    var hasMoved: Bool = false // Rok ve piyonun ilk hamlesi için

    static func == (lhs: ChessPiece, rhs: ChessPiece) -> Bool {
        lhs.id == rhs.id && lhs.position == rhs.position && lhs.hasMoved == rhs.hasMoved
    }
}

struct BoardPosition: Hashable, Equatable {
    var row: Int
    var col: Int

    // Tahta sınırları içinde mi?
    var isValid: Bool {
        return row >= 0 && row < 8 && col >= 0 && col < 8
    }

    // İki pozisyon arasındaki fark (vektör)
    static func - (lhs: BoardPosition, rhs: BoardPosition) -> (dr: Int, dc: Int) {
        return (lhs.row - rhs.row, lhs.col - rhs.col)
    }
    
    // Pozisyona vektör ekleme
    static func + (lhs: BoardPosition, rhs: (dr: Int, dc: Int)) -> BoardPosition {
        return BoardPosition(row: lhs.row + rhs.dr, col: lhs.col + rhs.dc)
    }
}

// Bir hamleyi temsil eden yapı
struct Move: Hashable {
    let from: BoardPosition
    let to: BoardPosition
    var isCastleKingside: Bool = false
    var isCastleQueenside: Bool = false
    var isEnPassantCapture: Bool = false
    var capturedPiecePosition: BoardPosition? = nil // En passant için
    var promotionType: PieceType? = nil // Piyon terfisi için
}

enum GameStatus {
    case ongoing
    case checkmate
    case stalemate
    case draw // Diğer berabere durumları eklenebilir (örn: 50 hamle kuralı)
}


// MARK: - Oyun Yönetimi (ViewModel)

class ChessGameViewModel: ObservableObject {
    @Published var board: [[ChessPiece?]]
    @Published var selectedPiecePosition: BoardPosition? = nil
    @Published var possibleMoves: Set<Move> = [] // Artık Move objeleri tutuyoruz
    @Published var currentPlayer: PieceColor = .white
    @Published var gameStatus: GameStatus = .ongoing
    @Published var statusMessage: String = "Sıra: Beyaz"
    @Published var lastMove: Move? = nil

    // Rok hakları
    private var whiteCanCastleKingside: Bool = true
    private var whiteCanCastleQueenside: Bool = true
    private var blackCanCastleKingside: Bool = true
    private var blackCanCastleQueenside: Bool = true

    // Geçerken alma (En Passant) hedef karesi
    private var enPassantTarget: BoardPosition? = nil

    init() {
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        setupInitialBoard()
        updateStatusMessage()
    }

    // MARK: - Kurulum
    func setupInitialBoard() {
        // Tümünü temizle (yeniden başlatma için)
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        whiteCanCastleKingside = true
        whiteCanCastleQueenside = true
        blackCanCastleKingside = true
        blackCanCastleQueenside = true
        enPassantTarget = nil
        selectedPiecePosition = nil
        possibleMoves = []
        currentPlayer = .white
        gameStatus = .ongoing
        lastMove = nil


        // Taşları yerleştir
        let pieceTypes: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for (col, type) in pieceTypes.enumerated() {
            placePiece(ChessPiece(type: type, color: .black, position: BoardPosition(row: 0, col: col)))
            placePiece(ChessPiece(type: .pawn, color: .black, position: BoardPosition(row: 1, col: col)))
            placePiece(ChessPiece(type: .pawn, color: .white, position: BoardPosition(row: 6, col: col)))
            placePiece(ChessPiece(type: type, color: .white, position: BoardPosition(row: 7, col: col)))
        }
        updateStatusMessage()
    }

    func placePiece(_ piece: ChessPiece?) {
        guard let piece = piece, piece.position.isValid else { return }
        board[piece.position.row][piece.position.col] = piece
    }

    // MARK: - Kullanıcı Etkileşimi
    func squareTapped(position: BoardPosition) {
        guard gameStatus == .ongoing else { return } // Oyun bittiyse işlem yapma

        if let selectedPos = selectedPiecePosition {
            // Seçili bir taş varsa
            let potentialMove = possibleMoves.first { $0.to == position }

            if let move = potentialMove {
                // Tıklanan kare geçerli bir hamle ise, hamleyi yap
                makeMove(move)
                selectedPiecePosition = nil
                possibleMoves = []
            } else {
                // Tıklanan kare geçerli bir hamle değilse
                selectedPiecePosition = nil // Seçimi kaldır
                possibleMoves = []
                // Eğer tıklanan karede kendi taşı varsa, onu seç
                if let piece = pieceAt(position), piece.color == currentPlayer {
                    selectedPiecePosition = position
                    generatePossibleMoves(for: piece)
                }
            }
        } else {
            // Seçili bir taş yoksa ve tıklanan karede oyuncunun taşı varsa, onu seç
            if let piece = pieceAt(position), piece.color == currentPlayer {
                selectedPiecePosition = position
                generatePossibleMoves(for: piece)
            }
        }
    }
    
    // MARK: - Hamle Yapma
    func makeMove(_ move: Move) {
        guard gameStatus == .ongoing, var pieceToMove = pieceAt(move.from) else { return }

        // Bir sonraki hamle için en passant hedefini temizle
        let previousEnPassantTarget = enPassantTarget
        enPassantTarget = nil

        // Eski pozisyonu temizle
        board[move.from.row][move.from.col] = nil

        // Özel Hamleler
        if move.isCastleKingside {
            // Şahı hareket ettir
            pieceToMove.position = move.to
            pieceToMove.hasMoved = true
            placePiece(pieceToMove)
            // Kaleyi hareket ettir
            if var rook = pieceAt(BoardPosition(row: move.from.row, col: 7)) {
                board[move.from.row][7] = nil // Eski kale pozisyonunu temizle
                rook.position = BoardPosition(row: move.from.row, col: 5)
                rook.hasMoved = true
                placePiece(rook)
            }
        } else if move.isCastleQueenside {
            // Şahı hareket ettir
            pieceToMove.position = move.to
            pieceToMove.hasMoved = true
            placePiece(pieceToMove)
            // Kaleyi hareket ettir
            if var rook = pieceAt(BoardPosition(row: move.from.row, col: 0)) {
                board[move.from.row][0] = nil // Eski kale pozisyonunu temizle
                rook.position = BoardPosition(row: move.from.row, col: 3)
                rook.hasMoved = true
                placePiece(rook)
            }
        } else if move.isEnPassantCapture {
            // Taşı hareket ettir
            pieceToMove.position = move.to
            pieceToMove.hasMoved = true
            placePiece(pieceToMove)
            // Rakip piyonu tahtadan kaldır
             guard let capturedPiecePos = move.capturedPiecePosition else {
                 print("Hata: En passant yakalama pozisyonu eksik!")
                 return // veya başka bir hata yönetimi
             }
            board[capturedPiecePos.row][capturedPiecePos.col] = nil
        } else {
            // Normal Hamle veya Normal Yakalama
            // Hedef karedeki taşı (varsa) kaldır - Yakalama
             // let capturedPiece = pieceAt(move.to) // İleride kullanılabilir (örn: yakalanan taşları gösterme)
            board[move.to.row][move.to.col] = nil // Önce hedefi temizle

            // Taşı yeni pozisyona yerleştir
            pieceToMove.position = move.to
            pieceToMove.hasMoved = true // Taş hareket etti

            // Piyon Terfisi
            if pieceToMove.type == .pawn && (move.to.row == 0 || move.to.row == 7) {
                // Basitlik adına otomatik Vezir'e terfi et
                pieceToMove.type = move.promotionType ?? .queen // Varsayılan Vezir
                 // TODO: Kullanıcıya seçim sunmak için UI eklenmeli
            }
            
            // Piyon 2 kare ileri gittiyse en passant hedefi ayarla
            if pieceToMove.type == .pawn && abs(move.to.row - move.from.row) == 2 {
                enPassantTarget = BoardPosition(row: (move.from.row + move.to.row) / 2, col: move.from.col)
            }

            placePiece(pieceToMove)
        }
        
        // Rok haklarını güncelle
        updateCastlingRights(movedPiece: pieceToMove, from: move.from)

        // Sırayı değiştir
        currentPlayer = currentPlayer.opposite
        
        // Son hamleyi kaydet
        lastMove = move

        // Oyun durumunu kontrol et (mat/pat)
        updateGameStatus()
        updateStatusMessage()
    }

    // MARK: - Oyun Durumu ve Kurallar
    
    func updateCastlingRights(movedPiece: ChessPiece, from: BoardPosition) {
        if movedPiece.type == .king {
            if movedPiece.color == .white {
                whiteCanCastleKingside = false
                whiteCanCastleQueenside = false
            } else {
                blackCanCastleKingside = false
                blackCanCastleQueenside = false
            }
        } else if movedPiece.type == .rook {
            if movedPiece.color == .white {
                if from == BoardPosition(row: 7, col: 0) { whiteCanCastleQueenside = false }
                if from == BoardPosition(row: 7, col: 7) { whiteCanCastleKingside = false }
            } else {
                if from == BoardPosition(row: 0, col: 0) { blackCanCastleQueenside = false }
                if from == BoardPosition(row: 0, col: 7) { blackCanCastleKingside = false }
            }
        }
        // Eğer hedef karede bir kale varsa (yeme durumu) onun da rok hakkı kaybolur
        // Not: Bu makeMove içinde zaten hedef kare temizlendiği için, bu kontrol
        // makeMove çağrılmadan *önce* yapılabilir veya yakalanan taş bilgisi saklanabilir.
        // Şimdilik yukarıdaki kontroller yeterli olacaktır.
    }
    
    func updateGameStatus() {
        let legalMoves = getAllLegalMoves(for: currentPlayer)

        if legalMoves.isEmpty {
            if isKingInCheck(color: currentPlayer) {
                gameStatus = .checkmate
            } else {
                gameStatus = .stalemate
            }
        } else {
            gameStatus = .ongoing
        }
    }

    func updateStatusMessage() {
        switch gameStatus {
        case .ongoing:
            let checkString = isKingInCheck(color: currentPlayer) ? " (ŞAH!)" : ""
            statusMessage = "Sıra: \(currentPlayer.rawValue)\(checkString)"
        case .checkmate:
            statusMessage = "ŞAH MAT! \(currentPlayer.opposite.rawValue) kazandı."
        case .stalemate:
            statusMessage = "PAT! Oyun berabere."
        case .draw:
             statusMessage = "Oyun berabere." // Diğer berabere durumları için
        }
    }

    // Belirli bir taş için olası hamleleri hesapla ve state'i güncelle
    func generatePossibleMoves(for piece: ChessPiece) {
        guard piece.color == currentPlayer else {
            possibleMoves = []
            return
        }
        let allLegalMoves = getAllLegalMoves(for: currentPlayer)
        // Sadece seçilen taşa ait olan legal hamleleri filtrele
        possibleMoves = allLegalMoves.filter { $0.from == piece.position }
    }

    // Bir oyuncu için TÜM yasal hamleleri üretir
    func getAllLegalMoves(for color: PieceColor) -> Set<Move> {
        var legalMoves: Set<Move> = []
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == color {
                    let pseudoLegalMoves = generatePseudoLegalMoves(for: piece)
                    for move in pseudoLegalMoves {
                        if isMoveLegal(move: move, color: color) {
                            legalMoves.insert(move)
                        }
                    }
                }
            }
        }
        return legalMoves
    }

    // Bir hamlenin şah durumuna yol açıp açmadığını kontrol eder
    func isMoveLegal(move: Move, color: PieceColor) -> Bool {
        // Hamleyi geçici olarak yap
        let originalBoard = board // Mevcut durumu kaydet
        let originalEnPassant = enPassantTarget
        let originalCastlingRights = (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside)

        // Simüle etme - Basit taşıma (Rok ve En Passant özel durumları daha dikkatli ele alınmalı)
        var tempPiece = pieceAt(move.from)!
        let capturedPiece = pieceAt(move.to) // Yakalanan taşı sakla (rok için önemli değil)
        
        board[move.to.row][move.to.col] = tempPiece // Taşı hareket ettir
        board[move.from.row][move.from.col] = nil  // Eski yeri boşalt
        
        if move.isEnPassantCapture {
             guard let capturedPos = move.capturedPiecePosition else { return false } // Güvenlik kontrolü
             board[capturedPos.row][capturedPos.col] = nil // En passant ile yakalanan piyonu kaldır
        }
        // Rok simülasyonu daha karmaşık, şimdilik sadece şah hareketini kontrol ediyoruz
        // Gerçek rok kontrolü isSquareAttacked içinde zaten yapılıyor


        // Hamle sonrası şah durumu kontrolü
        let kingInCheckAfterMove = isKingInCheck(color: color)

        // Tahtayı geri yükle
        board = originalBoard
        enPassantTarget = originalEnPassant
        (whiteCanCastleKingside, whiteCanCastleQueenside, blackCanCastleKingside, blackCanCastleQueenside) = originalCastlingRights


        return !kingInCheckAfterMove
    }


    // Şah tehdit altında mı kontrolü
    func isKingInCheck(color: PieceColor) -> Bool {
        guard let kingPosition = findKingPosition(for: color) else {
            // print("Hata: \(color.rawValue) Şah bulunamadı!")
            return false // Şah yoksa şah olamaz? Ya da hata durumu.
        }
        return isSquareAttacked(position: kingPosition, by: color.opposite)
    }

    // Belirli bir karenin rakip tarafından tehdit edilip edilmediğini kontrol eder
    func isSquareAttacked(position: BoardPosition, by attackerColor: PieceColor) -> Bool {
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == attackerColor {
                    // Rakip taşın pseudo-legal hamlelerini al (şah kontrolü yapmadan)
                    // Bu, döngüsel bağımlılığı önler (isSquareAttacked -> getLegalMoves -> isSquareAttacked...)
                    let moves = generatePseudoLegalMoves(for: piece, attackCheckOnly: true)
                    if moves.contains(where: { $0.to == position }) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    // Belirli bir renkteki şahın pozisyonunu bulur
    func findKingPosition(for color: PieceColor) -> BoardPosition? {
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.type == .king && piece.color == color {
                    return piece.position
                }
            }
        }
        return nil
    }

    // Bir taş için (şah kontrolü yapmadan) olası tüm hamleleri üretir
    // attackCheckOnly: Sadece tehdit kontrolü için mi kullanılıyor? (Piyonun sadece yeme hamlelerini üretir)
    func generatePseudoLegalMoves(for piece: ChessPiece, attackCheckOnly: Bool = false) -> Set<Move> {
        var moves: Set<Move> = []
        let pos = piece.position
        let color = piece.color

        switch piece.type {
        case .pawn:
            let direction = (color == .white) ? -1 : 1 // Beyaz yukarı (-1), Siyah aşağı (+1) gider
            let startRow = (color == .white) ? 6 : 1
            let promotionRow = (color == .white) ? 0 : 7

            // 1. Tek kare ileri
            let oneStep = pos + (dr: direction, dc: 0)
            if oneStep.isValid && pieceAt(oneStep) == nil && !attackCheckOnly {
                if oneStep.row == promotionRow {
                    // Terfi hamleleri (şimdilik sadece Vezir)
                    [.queen, .rook, .bishop, .knight].forEach { type in
                        moves.insert(Move(from: pos, to: oneStep, promotionType: type))
                    }
                } else {
                    moves.insert(Move(from: pos, to: oneStep))
                }
                
                // 2. İki kare ileri (başlangıç pozisyonundaysa ve önü boşsa)
                if pos.row == startRow {
                    let twoSteps = pos + (dr: 2 * direction, dc: 0)
                    if twoSteps.isValid && pieceAt(twoSteps) == nil {
                        moves.insert(Move(from: pos, to: twoSteps))
                    }
                }
            }

            // 3. Çapraz yeme
            for dc in [-1, 1] {
                let capturePos = pos + (dr: direction, dc: dc)
                if capturePos.isValid {
                    if let targetPiece = pieceAt(capturePos), targetPiece.color != color {
                         if capturePos.row == promotionRow && !attackCheckOnly {
                            // Terfi ile yeme
                             [.queen, .rook, .bishop, .knight].forEach { type in
                                 moves.insert(Move(from: pos, to: capturePos, promotionType: type))
                             }
                        } else {
                             moves.insert(Move(from: pos, to: capturePos))
                        }
                    }
                    // 4. Geçerken Alma (En Passant)
                    else if capturePos == enPassantTarget && !attackCheckOnly {
                         // Yakalanacak piyonun pozisyonunu belirle
                        let capturedPawnPos = BoardPosition(row: pos.row, col: capturePos.col)
                        moves.insert(Move(from: pos, to: capturePos, isEnPassantCapture: true, capturedPiecePosition: capturedPawnPos))
                    }
                }
            }

        case .knight:
            let knightMoves: [(dr: Int, dc: Int)] = [
                (-2, -1), (-2, 1), (-1, -2), (-1, 2),
                (1, -2), (1, 2), (2, -1), (2, 1)
            ]
            for moveOffset in knightMoves {
                let targetPos = pos + moveOffset
                if targetPos.isValid {
                    if let targetPiece = pieceAt(targetPos) {
                        if targetPiece.color != color { // Rakip taşı yiyebilir
                            moves.insert(Move(from: pos, to: targetPos))
                        }
                    } else { // Boş kareye gidebilir
                        moves.insert(Move(from: pos, to: targetPos))
                    }
                }
            }

        case .bishop, .rook, .queen:
            var directions: [(dr: Int, dc: Int)] = []
           if piece.type == .bishop || piece.type == .queen {
               directions += [(-1, -1), (-1, 1), (1, -1), (1, 1)] // Çapraz (+= ile düzeltildi)
           }
           if piece.type == .rook || piece.type == .queen {
               directions += [(-1, 0), (1, 0), (0, -1), (0, 1)] // Düz (+= ile düzeltildi)
           }

            for dir in directions {
                var currentPos = pos + dir
                while currentPos.isValid {
                    if let targetPiece = pieceAt(currentPos) {
                        if targetPiece.color != color { // Rakip taşı yiyebilir
                            moves.insert(Move(from: pos, to: currentPos))
                        }
                        break // Kendi veya rakip taşına rastlayınca o yönde dur
                    } else { // Boş kareye gidebilir
                        moves.insert(Move(from: pos, to: currentPos))
                    }
                    currentPos = currentPos + dir // Aynı yönde devam et
                }
            }
            
         case .king:
             let kingMoves: [(dr: Int, dc: Int)] = [
                 (-1, -1), (-1, 0), (-1, 1),
                 (0, -1),           (0, 1),
                 (1, -1), (1, 0), (1, 1)
             ]
             // Normal 1 kare hareketler
             for moveOffset in kingMoves {
                 let targetPos = pos + moveOffset
                 if targetPos.isValid {
                     if let targetPiece = pieceAt(targetPos) {
                         if targetPiece.color != color {
                             moves.insert(Move(from: pos, to: targetPos))
                         }
                     } else {
                         moves.insert(Move(from: pos, to: targetPos))
                     }
                 }
             }
             
             // Rok (Castling) - Sadece legal hamle kontrolü sırasında değil, pseudo-legal'da eklenir,
             // sonra isMoveLegal ile şah durumu kontrol edilir.
             if !piece.hasMoved && !attackCheckOnly && !isKingInCheck(color: color) { // Şah daha önce oynamadıysa ve şu an şah altında değilse
                 let row = pos.row
                 // Şah tarafı (Kısa Rok)
                 if (color == .white ? whiteCanCastleKingside : blackCanCastleKingside) {
                     if pieceAt(BoardPosition(row: row, col: 5)) == nil &&
                        pieceAt(BoardPosition(row: row, col: 6)) == nil &&
                        !isSquareAttacked(position: BoardPosition(row: row, col: 5), by: color.opposite) &&
                        !isSquareAttacked(position: BoardPosition(row: row, col: 6), by: color.opposite) {
                            // Kale kontrolü (var mı ve oynamamış mı)
                            if let rook = pieceAt(BoardPosition(row: row, col: 7)), rook.type == .rook, !rook.hasMoved {
                                moves.insert(Move(from: pos, to: BoardPosition(row: row, col: 6), isCastleKingside: true))
                            }
                     }
                 }
                 // Vezir tarafı (Uzun Rok)
                  if (color == .white ? whiteCanCastleQueenside : blackCanCastleQueenside) {
                     if pieceAt(BoardPosition(row: row, col: 1)) == nil &&
                        pieceAt(BoardPosition(row: row, col: 2)) == nil &&
                        pieceAt(BoardPosition(row: row, col: 3)) == nil &&
                        !isSquareAttacked(position: BoardPosition(row: row, col: 2), by: color.opposite) &&
                        !isSquareAttacked(position: BoardPosition(row: row, col: 3), by: color.opposite) {
                             // Kale kontrolü (var mı ve oynamamış mı)
                             if let rook = pieceAt(BoardPosition(row: row, col: 0)), rook.type == .rook, !rook.hasMoved {
                                 moves.insert(Move(from: pos, to: BoardPosition(row: row, col: 2), isCastleQueenside: true))
                             }
                     }
                 }
             }
        }

        return moves
    }
    
    // Belirtilen pozisyondaki taşı döndürür (güvenli erişim)
    func pieceAt(_ position: BoardPosition) -> ChessPiece? {
        guard position.isValid else { return nil }
        return board[position.row][position.col]
    }
}

// MARK: - SwiftUI Görünümleri

struct ContentView: View {
    @StateObject private var viewModel = ChessGameViewModel()
    let squareSize: CGFloat = UIScreen.main.bounds.width / 8.5 // Ekran genişliğine göre ayarla

    var body: some View {
        NavigationView {
            VStack(spacing: 1) {
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .padding(.vertical, 5)

                ChessBoardView(viewModel: viewModel, squareSize: squareSize)

                // Yakalanan taşlar veya diğer bilgiler buraya eklenebilir
                Spacer() // Boşluk ekleyerek tahtayı yukarı iter
            }
            .padding(.horizontal, squareSize * 0.25) // Kenarlara hafif boşluk
            .background(Color(UIColor.systemGroupedBackground)) // Hafif arkaplan rengi
            .navigationTitle("Swift Satranç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.setupInitialBoard() // Oyunu yeniden başlat
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
             // Oyun bittiğinde uyarı göster
             .alert("Oyun Bitti!", isPresented: .constant(viewModel.gameStatus != .ongoing), actions: {
                 Button("Yeni Oyun") {
                     viewModel.setupInitialBoard()
                 }
                 Button("Kapat", role: .cancel) {}
             }, message: {
                 Text(viewModel.statusMessage)
             })
        }
         // Dikey yönlendirmeye zorla (isteğe bağlı)
         .navigationViewStyle(.stack) // iPad'de tam ekran için
         // .supportedOrientations(.portrait) // Sadece dikey mod için (Info.plist ayarı da gerekebilir)

    }
}

struct ChessBoardView: View {
    @ObservedObject var viewModel: ChessGameViewModel
    let squareSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let position = BoardPosition(row: row, col: col)
                        SquareView(
                            position: position,
                            piece: viewModel.pieceAt(position),
                            isPossibleMove: viewModel.possibleMoves.contains { $0.to == position },
                            isSelected: viewModel.selectedPiecePosition == position,
                            isCheck: (viewModel.pieceAt(position)?.type == .king && viewModel.isKingInCheck(color: viewModel.pieceAt(position)!.color)),
                            isLastMove: viewModel.lastMove?.from == position || viewModel.lastMove?.to == position,
                            size: squareSize
                        )
                        .onTapGesture {
                            viewModel.squareTapped(position: position)
                        }
                    }
                }
            }
        }
        .overlay( // Tahtaya çerçeve ekle
             Rectangle()
                 .stroke(Color.black.opacity(0.7), lineWidth: 1)
         )
    }
}


struct SquareView: View {
    let position: BoardPosition
    let piece: ChessPiece?
    let isPossibleMove: Bool
    let isSelected: Bool
    let isCheck: Bool // Şahın olduğu kare şah durumunda mı?
    let isLastMove: Bool // Son hamlenin yapıldığı kare mi?
    let size: CGFloat

    var body: some View {
        ZStack {
            // Kare Rengi
            Rectangle()
                .fill(squareColor)
                .frame(width: size, height: size)
            
            // Son Hamle Vurgusu
             if isLastMove {
                 Rectangle()
                     .fill(Color.yellow.opacity(0.3))
                     .frame(width: size, height: size)
             }

            // Seçili Kare Vurgusu
            if isSelected {
                Rectangle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: size - 1.5, height: size - 1.5) // İçeride
            }
            
            // Şah Vurgusu
            if isCheck {
                 Rectangle()
                     .fill(Color.red.opacity(0.6))
                     .frame(width: size, height: size)
            }

            // Olası Hamle Göstergesi (nokta)
            if isPossibleMove {
                // Hedefte taş varsa halka, boşsa dolu daire
                if piece != nil { // Rakip taşın olduğu yer
                    Circle()
                        .stroke(Color.green.opacity(0.7), lineWidth: size * 0.1)
                        .frame(width: size * 0.85, height: size * 0.85)

                } else { // Boş kare
                    Circle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: size * 0.3, height: size * 0.3)
                }
            }

            // Taş Sembolü
            if let piece = piece {
                Text(piece.type.getSymbol(color: piece.color))
                    .font(.system(size: size * 0.75)) // Boyut ayarı
                    .minimumScaleFactor(0.5) // Küçük ekranlarda sığmazsa küçült
                    .lineLimit(1)
                    .foregroundColor(piece.color == .white ? .white.opacity(0.95) : .black.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0.5, y: 0.5)
            }
        }
    }

    // Kare rengi (açık/koyu)
    private var squareColor: Color {
        (position.row + position.col) % 2 == 0 ? Color(white: 0.9) : Color(white: 0.4) // Gri tonları
    }
}

// MARK: - Uygulama Giriş Noktası

*/
