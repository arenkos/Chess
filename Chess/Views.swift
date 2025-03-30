//
//  Views.swift
//  Chess
//
//  Created by Aren Koş on 31.03.2025.
//

import SwiftUI
import Foundation
// Models.swift ve GameViewModel.swift dosyalarının içeriğine erişim için UIKit gerekliyse
import UIKit

// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.gameStatus != .setup {
                    GameAreaView(viewModel: viewModel)
                } else {
                    // SetupView normalde sheet olarak sunulur,
                    // ama başlangıçta doğrudan gösterilebilir.
                     Text("Oyun Yükleniyor...") // Veya doğrudan SetupView göster
                         .onAppear {
                             // İlk açılışta setup sheet'i göster
                         }
                }
            }
            .navigationTitle(viewModel.isAgainstComputer ? "Bilgisayara Karşı" : "İki Kişilik Oyun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Oyun devam ederken yeniden başlatma butonu
                 if viewModel.gameStatus != .setup {
                    ToolbarItem(placement: .navigationBarLeading) {
                         Button {
                             viewModel.gameStatus = .setup // Ayar ekranına dön
                             viewModel.stopTimer() // Zamanlayıcıyı durdur
                             viewModel.statusMessage = "Ayarları Yapın"
                         } label: {
                             Image(systemName: "gearshape.fill")
                         }
                     }
                     ToolbarItem(placement: .navigationBarTrailing) {
                          Button("Yeni Oyun") {
                              viewModel.startGame() // Ayarlara göre yeni oyun başlat
                          }
                      }
                 }
            }
             // Setup sheet
             .sheet(isPresented: .constant(viewModel.gameStatus == .setup), onDismiss: {
                 if viewModel.moveHistory.isEmpty { // Henüz oyun başlamadıysa
                     // viewModel.gameStatus = .setup // Tekrar göstermeye zorla
                 }
             }) {
                 SetupView(viewModel: viewModel)
             }
             // Oyun Sonu Uyarısı
              .alert("Oyun Bitti!", isPresented: .constant(viewModel.gameStatus != .ongoing && viewModel.gameStatus != .setup), actions: {
                  Button("Yeni Oyun") { viewModel.startGame() }
                  Button("Ayarlar") { viewModel.gameStatus = .setup }
              }, message: {
                  Text(viewModel.statusMessage) // Mat, Pat, Süre Bitti mesajı
              })
        }
        .navigationViewStyle(.stack) // iPad için daha iyi görünüm
    }
}

// MARK: - Game Area (Board, Timers, Notation)
struct GameAreaView: View {
    @ObservedObject var viewModel: GameViewModel
    private let boardSize: CGFloat = UIScreen.main.bounds.width * 0.9 // Ekran genişliğinin %90'ı
    @State private var boardRotation: Double = 0 // Tahtanın dönüş açısı
    @State private var passDeviceTimer: Timer? = nil // Cihazı geçiş zamanlayıcısı

    var body: some View {
        ZStack {
            // Arka plan rengi, tahtanın çevrilmiş halinde de tutarlı bir görüntü sağlar
            Color(.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 10) {
                // Rakip Zamanlayıcı (Üstte)
                let upperPlayerWhite = viewModel.isBoardFlipped // Çevrili tahtada üstteki beyaz olur
                TimerView(timeRemaining: upperPlayerWhite ? viewModel.whiteTimeRemaining : viewModel.blackTimeRemaining,
                          isActive: viewModel.activeTimerColor == (upperPlayerWhite ? .white : .black),
                          viewModel: viewModel)

                // Tahta ve Koordinatlar
                BoardWithCoordinatesView(viewModel: viewModel, boardSize: boardSize)

                // Oyuncu Zamanlayıcı (Altta)
                let lowerPlayerWhite = !viewModel.isBoardFlipped // Çevrili olmayan tahtada alttaki beyaz olur
                TimerView(timeRemaining: lowerPlayerWhite ? viewModel.whiteTimeRemaining : viewModel.blackTimeRemaining,
                          isActive: viewModel.activeTimerColor == (lowerPlayerWhite ? .white : .black),
                          viewModel: viewModel)
                
                // Durum Mesajı
                Text(viewModel.statusMessage)
                     .font(.headline)
                     .padding(.vertical, 5)

                // Hamle Notasyonu - iki kişilik oyun için ortak görünüm
                NotationView(moves: viewModel.moveHistory, isFlipped: viewModel.isBoardFlipped)
                    .frame(height: 100) // Yüksekliği sınırla
                
                // İki kişilik oyun için cihazı ters çevirme düğmesi
                if !viewModel.isAgainstComputer {
                    Button(action: {
                        flipBoard()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("Tahtayı Çevir")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .padding(.top, 5)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, boardSize * 0.05) // Kenar boşlukları
            // İki kişilik oyun için 180 derece döndürme
            .rotationEffect(.degrees(boardRotation))
            .animation(.easeInOut(duration: 0.5), value: boardRotation)
            
            // Geçiş uyarısı (180 dereceye döndürüldüğünde)
            if passDeviceTimer != nil {
                VStack {
                    Text("Cihazı Rakibinize Verin")
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
                .edgesIgnoringSafeArea(.all)
            }
        }
        // Hamle yapıldığında tahtanın otomatik döndürülmesi için
        .onChange(of: viewModel.currentPlayer) { newPlayer in
            if !viewModel.isAgainstComputer && viewModel.gameStatus == .ongoing {
                // Sıra değiştiğinde otomatik döndür
                boardRotation += 180 // Tahtayı doğrudan 180 derece döndür
                if boardRotation >= 360 {
                    boardRotation = 0
                }
                startPassDeviceAnimation() // Sadece uyarı göster
            }
        }
    }
    
    // Tahtayı 180 derece çevir ve geçiş animasyonu göster
    private func flipBoard() {
        boardRotation += 180
        
        if boardRotation >= 360 {
            boardRotation = 0
        }
        
        // Uyarı göster
        startPassDeviceAnimation()
    }
    
    // Cihazı geçiş animasyonu
    private func startPassDeviceAnimation() {
        // Artık tahtayı burada döndürmüyoruz, onChange fonksiyonunda yapılıyor
        
        // Eğer bir zamanlayıcı zaten çalışıyorsa iptal et
        passDeviceTimer?.invalidate()
        
        // Yeni zamanlayıcı oluştur ve 2 saniye sonra görünümü kaldır
        passDeviceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            passDeviceTimer = nil
        }
    }
}


// MARK: - Setup View
struct SetupView: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) var dismiss // Sheet'i kapatmak için

    // Geçici ayar değerleri
    @State private var selectedColor: PieceColor
    @State private var selectedBaseTime: Int
    @State private var selectedIncrement: Int
    @State private var isAgainstComputer: Bool
    @State private var selectedDifficulty: Int

     // Zaman seçenekleri
     let timeOptions = [0, 1, 3, 5, 10, 15, 30, 60] // Dakika
     let incrementOptions = [0, 1, 2, 3, 5, 10, 15] // Saniye
     let difficultyLevels = [1, 2, 3, 4, 5] // Zorluk seviyeleri

    init(viewModel: GameViewModel) {
        self.viewModel = viewModel
        // ViewModel'deki mevcut ayarlarla başla
        _selectedColor = State(initialValue: viewModel.playerSettings.playerColor)
        _selectedBaseTime = State(initialValue: viewModel.playerSettings.timeControl.baseMinutes)
        _selectedIncrement = State(initialValue: viewModel.playerSettings.timeControl.incrementSeconds)
        _isAgainstComputer = State(initialValue: viewModel.playerSettings.isAgainstComputer)
        _selectedDifficulty = State(initialValue: viewModel.playerSettings.computerDifficulty)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Oyun Modu") {
                    Picker("Mod", selection: $isAgainstComputer) {
                        Text("Rakibe Karşı").tag(false)
                        Text("Bilgisayara Karşı").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if isAgainstComputer {
                        Picker("Zorluk Seviyesi", selection: $selectedDifficulty) {
                            ForEach(difficultyLevels, id: \.self) { level in
                                Text("\(level)").tag(level)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section("Oyuncu Ayarları") {
                    Picker("Rengim (Alttaki Taraf)", selection: $selectedColor) {
                        ForEach(PieceColor.allCases) { color in
                            Text(color.rawValue).tag(color)
                        }
                    }
                }

                Section("Zaman Kontrolü") {
                     Picker("Başlangıç Süresi (Dakika)", selection: $selectedBaseTime) {
                         ForEach(timeOptions, id: \.self) { time in
                             Text(time == 0 ? "Süresiz" : "\(time) dk").tag(time)
                         }
                     }
                    // Sadece süre varsa increment göster
                     if selectedBaseTime > 0 {
                         Picker("Hamle Başına Ek Süre (Saniye)", selection: $selectedIncrement) {
                             ForEach(incrementOptions, id: \.self) { inc in
                                 Text("\(inc) sn").tag(inc)
                             }
                         }
                     } else {
                         // Süresiz seçilince increment'i sıfırla
                         Text("Hamle Başına Ek Süre: Yok")
                             .foregroundColor(.gray)
                             .onAppear { selectedIncrement = 0 }
                     }
                }

                Button("Oyunu Başlat") {
                    // Seçilen ayarları ViewModel'a aktar
                    viewModel.playerSettings.playerColor = selectedColor
                    viewModel.playerSettings.timeControl = TimeControl(baseMinutes: selectedBaseTime, incrementSeconds: selectedIncrement)
                    viewModel.playerSettings.isAgainstComputer = isAgainstComputer
                    viewModel.playerSettings.computerDifficulty = selectedDifficulty
                    
                    // Oyun modunu ayarla
                    viewModel.setGameMode(againstComputer: isAgainstComputer, difficulty: selectedDifficulty)
                    
                    // Oyunu başlat
                    viewModel.startGame()
                    
                    // Sheet'i kapat
                    dismiss()
                }
            }
            .navigationTitle("Oyun Ayarları")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Board with Coordinates
struct BoardWithCoordinatesView: View {
    @ObservedObject var viewModel: GameViewModel
    let boardSize: CGFloat
    var squareSize: CGFloat { boardSize / 8 }

    var body: some View {
        HStack(spacing: 2) {
            // Sol Rank Numaraları (8'den 1'e veya 1'den 8'e)
            VStack(spacing: 0) {
                if viewModel.isBoardFlipped {
                    ForEach(1...8, id: \.self) { rank in
                        Text("\(rank)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 15, height: squareSize) // Genişliği ayarla
                    }
                } else {
                    ForEach((1...8).reversed(), id: \.self) { rank in
                        Text("\(rank)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 15, height: squareSize) // Genişliği ayarla
                    }
                }
            }

            VStack(spacing: 2) {
                 // Üst File Harfleri (a'dan h'ye veya h'den a'ya)
                 HStack(spacing: 0) {
                     ForEach(0..<8, id: \.self) { col in
                         let fileIndex = viewModel.isBoardFlipped ? 7 - col : col
                         Text(String(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(fileIndex))!))
                             .font(.caption.weight(.semibold))
                             .frame(width: squareSize, height: 15) // Yüksekliği ayarla
                     }
                 }
                
                // Asıl Satranç Tahtası
                 ChessBoardView(viewModel: viewModel, squareSize: squareSize)
                     .frame(width: boardSize, height: boardSize) // Tam boyut ver
                
                 // Alt File Harfleri (a'dan h'ye veya h'den a'ya)
                 HStack(spacing: 0) {
                      ForEach(0..<8, id: \.self) { col in
                          let fileIndex = viewModel.isBoardFlipped ? 7 - col : col
                          Text(String(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(fileIndex))!))
                              .font(.caption.weight(.semibold))
                              .frame(width: squareSize, height: 15)
                      }
                  }
            }
            // Sağ Rank Numaraları (8'den 1'e veya 1'den 8'e)
             VStack(spacing: 0) {
                 if viewModel.isBoardFlipped {
                     ForEach(1...8, id: \.self) { rank in
                         Text("\(rank)")
                             .font(.caption.weight(.semibold))
                             .frame(width: 15, height: squareSize)
                     }
                 } else {
                     ForEach((1...8).reversed(), id: \.self) { rank in
                         Text("\(rank)")
                             .font(.caption.weight(.semibold))
                             .frame(width: 15, height: squareSize)
                     }
                 }
             }
        }
    }
}


// MARK: - Chess Board View
struct ChessBoardView: View {
    @ObservedObject var viewModel: GameViewModel
    let squareSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { colIndex in
                        // Eğer tahta çevrildiyse, koordinatları tersine çevir
                        let row = viewModel.isBoardFlipped ? 7 - rowIndex : rowIndex
                        let col = viewModel.isBoardFlipped ? 7 - colIndex : colIndex
                        
                        let position = BoardPosition(row: row, col: col)
                        let piece = viewModel.pieceAt(position)
                        SquareView(
                            position: position,
                            piece: piece,
                            isPossibleMove: viewModel.possibleMoves.contains { $0.to == position },
                            isSelected: viewModel.selectedPiecePosition == position,
                            isCheck: (piece?.type == .king && (piece?.color == .white ? viewModel.whiteKingInCheck : viewModel.blackKingInCheck)),
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
        .overlay(Rectangle().stroke(Color.black.opacity(0.7), lineWidth: 1)) // Çerçeve
        .environmentObject(viewModel) // SquareView için viewModel'ı environment olarak ekle
    }
}


// MARK: - Square View
struct SquareView: View {
    @EnvironmentObject var viewModel: GameViewModel // isBoardFlipped erişimi için
    let position: BoardPosition
    let piece: ChessPiece?
    let isPossibleMove: Bool
    let isSelected: Bool
    let isCheck: Bool // Şahın olduğu kare şah durumunda mı?
    let isLastMove: Bool // Son hamlenin yapıldığı kare mi?
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(squareColor).frame(width: size, height: size)
            if isLastMove { Rectangle().fill(Color.yellow.opacity(0.3)).frame(width: size, height: size) }
            if isCheck { Rectangle().fill(Color.red.opacity(0.6)).frame(width: size, height: size) }
            if isSelected { Rectangle().stroke(Color.blue, lineWidth: 3).frame(width: size - 1.5, height: size - 1.5) }

            if isPossibleMove {
                if piece != nil { // Rakip taşın olduğu yer (Yakalama)
                     Circle().stroke(Color.green.opacity(0.7), lineWidth: size * 0.1).frame(width: size * 0.85, height: size * 0.85)
                } else { // Boş kare
                     Circle().fill(Color.green.opacity(0.5)).frame(width: size * 0.3, height: size * 0.3)
                }
            }

            if let p = piece {
                Text(p.type.getSymbol(color: p.color))
                    .font(.system(size: size * 0.75))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundColor(p.color == .white ? .white.opacity(0.95) : .black.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0.5, y: 0.5)
            }
        }
    }

    private var squareColor: Color { (position.row + position.col).isMultiple(of: 2) ? Color(white: 0.9) : Color(white: 0.4) }
}


// MARK: - Timer View
struct TimerView: View {
    let timeRemaining: TimeInterval
    let isActive: Bool // Bu oyuncunun sırası mı?
    @ObservedObject var viewModel: GameViewModel // formatTime'a erişim için

    var body: some View {
        Text(viewModel.formatTime(timeRemaining))
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
            .background(isActive ? Color.green.opacity(0.3) : Color.gray.opacity(0.2))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.green : Color.gray, lineWidth: 1)
            )
    }
}


// MARK: - Notation View
struct NotationView: View {
    let moves: [Move]
    let isFlipped: Bool
    
    // Hamle çiftlerini oluştur (Beyaz, Siyah) şeklinde
    private func createMovePairs() -> [(Int, Move, Move?)] {
        var pairs: [(Int, Move, Move?)] = []
        
        // Boş move listesini kontrol et
        guard !moves.isEmpty else { return [] }
        
        for i in stride(from: 0, to: moves.count, by: 2) {
            let moveNumber = i / 2 + 1
            
            // Array bounds kontrolü
            guard i < moves.count else { break }
            
            let whiteMove = moves[i]
            let blackMove: Move? = (i + 1 < moves.count) ? moves[i + 1] : nil
            
            pairs.append((moveNumber, whiteMove, blackMove))
        }
        
        return pairs
    }
    
    // Hamle çifti için görünüm - simetrik tasarım
    private func movePairView(moveNumber: Int, whiteMove: Move, blackMove: Move?) -> some View {
        HStack(spacing: 8) {
            // Hamle numarası
            Text("\(moveNumber).")
                .fontWeight(.semibold)
                .frame(width: 25, alignment: .center)
            
            // Beyaz hamle
            Text(whiteMove.notation ?? "?") 
                .id(whiteMove.id)
                .frame(minWidth: 50, alignment: .leading)
                .padding(.horizontal, 3)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
            
            // Siyah hamle (varsa)
            if let blackMove = blackMove {
                Text(blackMove.notation ?? "?")
                    .id(blackMove.id)
                    .frame(minWidth: 50, alignment: .leading)
                    .padding(.horizontal, 3)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(3)
            } else {
                // Siyah hamle yoksa boş alan bırak
                Spacer()
                    .frame(minWidth: 50)
            }
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        ScrollViewReader { proxy in // Son hamleye otomatik kaydırmak için
            ScrollView(.vertical) {
                VStack(alignment: .center, spacing: 2) {
                    HStack {
                        Text("No.")
                            .fontWeight(.bold)
                            .frame(width: 25)
                        Text("Beyaz")
                            .fontWeight(.bold)
                            .frame(minWidth: 50)
                        Text("Siyah")
                            .fontWeight(.bold)
                            .frame(minWidth: 50)
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.bottom, 4)
                    
                    // Hamle çiftlerini oluştur ve listele
                    let movePairs = createMovePairs()
                    
                    // Boş pairs kontrolü
                    if !movePairs.isEmpty {
                        ForEach(0..<movePairs.count, id: \.self) { index in
                            if index < movePairs.count { // Array bounds kontrolü
                                let pair = movePairs[index]
                                movePairView(moveNumber: pair.0, whiteMove: pair.1, blackMove: pair.2)
                            }
                        }
                    } else {
                        // Hamle yoksa boş bir text göster
                        Text("Henüz hamle yapılmadı")
                            .foregroundColor(.gray)
                            .italic()
                    }
                    
                    // ScrollView'un sonuna boş bir view ekleyerek ID ver
                    Spacer().frame(height: 0).id("bottom")
                }
                .padding(.horizontal, 5)
            }
            .onChange(of: moves.count) { _ in // Yeni hamle geldiğinde
                // Biraz gecikmeyle en sona veya son hamleye kaydır
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToLatestMove(proxy: proxy)
                }
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3)))
    }
    
    // Kaydırma mantığını ayrı bir fonksiyona ayır
    private func scrollToLatestMove(proxy: ScrollViewProxy) {
        let lastMove = moves.last
        
        if let lastMove = lastMove {
            withAnimation {
                proxy.scrollTo(lastMove.id, anchor: .bottom)
            }
        } else {
            withAnimation {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
