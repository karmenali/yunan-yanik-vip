import assert from 'assert';
import {
  Card,
  createDeck,
  dealRoundHands,
  evaluateHandOptimal,
  isValidMeld,
  selectBestAutoDiscard,
} from './engine/gameEngine';

function makeCard(id: string, suit: 'S' | 'H' | 'D' | 'C' | 'J', rank: number, isJoker = false): Card {
  return {
    id,
    suit,
    rank,
    deckIndex: 1,
    isPhysicalJoker: isJoker,
  };
}

console.log('🧪 Yanık İskambil HD Oyun Motoru Testleri Başlatılıyor...');

// 1. Deste Testi (106 Kağıt)
const deck = createDeck();
assert.strictEqual(deck.length, 106, 'Deste 106 kağıt olmalı (104 normal + 2 joker)');
const jokers = deck.filter((c) => c.isPhysicalJoker);
assert.strictEqual(jokers.length, 2, '2 adet fiziksel joker olmalı');

// 2. Dağıtım Testi (2'şer 2'şer 10 kağıt + Gösterge)
const deal = dealRoundHands(['p1', 'p2', 'p3', 'p4']);
assert.strictEqual(deal.hands['p1'].length, 10);
assert.strictEqual(deal.hands['p4'].length, 10);
assert.strictEqual(deal.drawPile.length, 66); // 106 - 40 = 66 (Gösterge en altta dahil)
assert.strictEqual(deal.drawPile[deal.drawPile.length - 1].id, deal.indicatorCard.id);

// 3. Grup Per Sembol Kuralı Testi (Semboller farklı olmalı!)
const validSet = [
  makeCard('1', 'S', 7),
  makeCard('2', 'H', 7),
  makeCard('3', 'D', 7),
];
assert.strictEqual(isValidMeld(validSet, 2), true, 'Farklı sembollü 7-7-7 geçerli olmalı');

const invalidDuplicateSuitSet = [
  makeCard('1', 'S', 7),
  makeCard('2', 'S', 7),
  makeCard('3', 'H', 7),
];
assert.strictEqual(
  isValidMeld(invalidDuplicateSuitSet, 2),
  false,
  'Aynı sembolden iki Maça 7 içeren grup per GEÇERSİZ olmalı'
);

// 4. Seri Per & As (1) Kuralı Testi (A-2-3 geçerli, Q-K-A geçerli, Q-K-A-2 geçersiz!)
const validLowAceRun = [
  makeCard('1', 'S', 1),
  makeCard('2', 'S', 2),
  makeCard('3', 'S', 3),
];
assert.strictEqual(isValidMeld(validLowAceRun, 9), true, 'Sinek A-2-3 geçerli olmalı');

const validHighAceRun = [
  makeCard('1', 'C', 12), // Q
  makeCard('2', 'C', 13), // K
  makeCard('3', 'C', 1),  // A
];
assert.strictEqual(isValidMeld(validHighAceRun, 9), true, 'Sinek Q-K-A geçerli olmalı');

const invalidWrapRun = [
  makeCard('1', 'C', 12), // Q
  makeCard('2', 'C', 13), // K
  makeCard('3', 'C', 1),  // A
  makeCard('4', 'C', 2),  // 2
];
assert.strictEqual(isValidMeld(invalidWrapRun, 9), false, 'Sinek Q-K-A-2 döngüsel seri GEÇERSİZ olmalı');

// 5. Gösterge Jokeri ve Ceza Puanı Testi (Wild Rank = 6)
// Elde: Kupa 6 (Gösterge Jokeri), Maça 10, Maça Q -> Kupa 6 araya girip Maça 10-J-Q yapar (0 puan!)
// Boşta: Karo As (11 puan), Sinek K (10 puan) -> Toplam ceza 21 olmalı!
const sampleHand = [
  makeCard('c1', 'H', 6),  // Gösterge Jokeri (6'lı)
  makeCard('c2', 'S', 10),
  makeCard('c3', 'S', 12), // Q
  makeCard('c4', 'D', 1),  // As (11p)
  makeCard('c5', 'C', 13), // K (10p)
];
const evalResult = evaluateHandOptimal(sampleHand, 6);
assert.strictEqual(evalResult.penalty, 21, 'Joker per yaptığı için 0 sayılmalı, kalan As(11)+K(10)=21 olmalı');

// 6. Boşta Kalan Joker 25 Puan Testi
const lonelyJokerHand = [
  makeCard('j1', 'J', 0, true), // Fiziksel Joker
  makeCard('c1', 'S', 2),       // 2p (Jokerle tek başına 3'lü per olamaz)
];
const lonelyEval = evaluateHandOptimal(lonelyJokerHand, 6);
assert.strictEqual(lonelyEval.penalty, 27, 'Per yapamayan Joker 25p + 2li (2p) = 27p olmalı');

// 7. 30 Saniye Otomatik Atış Testi (Per olmayan ve Joker olmayan en büyük kağıt atılmalı)
const hand11 = [
  makeCard('1', 'S', 4),
  makeCard('2', 'S', 5),
  makeCard('3', 'S', 6), // 4-5-6 per
  makeCard('4', 'J', 0, true), // Joker (atılmamalı!)
  makeCard('5', 'H', 3), // Boşta 3p
  makeCard('6', 'D', 1), // Boşta As = 11p (EN BÜYÜK GEREKSİZ KAĞIT!)
  makeCard('7', 'C', 9), // Boşta 9p
  makeCard('8', 'H', 8),
  makeCard('9', 'D', 8),
  makeCard('10', 'C', 8), // 8-8-8 per
  makeCard('11', 'S', 2), // Boşta 2p
];
const autoDiscarded = selectBestAutoDiscard(hand11, 6);
assert.strictEqual(autoDiscarded.id, '6', 'Otomatik atışta per olmayan ve joker olmayan en büyük kağıt (As = 11p) atılmalı');

console.log('✅ Tüm Yanık İskambil HD Oyun Motoru Testleri %100 Başarıyla Geçti!');
