export type Suit = 'S' | 'H' | 'D' | 'C' | 'J'; // Spades (Maça), Hearts (Kupa), Diamonds (Karo), Clubs (Sinek), Joker

export interface Card {
  id: string;
  suit: Suit;
  rank: number; // 1 (Ace) .. 13 (King), 0 for physical Joker
  deckIndex: number; // 1 or 2
  isPhysicalJoker: boolean;
}

export interface HandEvaluation {
  canFinish: boolean;
  melds: Card[][];
  unmelded: Card[];
  penalty: number;
  orderedCards: Card[];
}

/**
 * 106 kağıtlık Yunan Yanık destesi oluşturur (2 x 52 kağıt + 2 Fiziksel Joker)
 */
export function createDeck(): Card[] {
  const suits: Suit[] = ['S', 'H', 'D', 'C'];
  const deck: Card[] = [];

  for (let d = 1; d <= 2; d++) {
    for (const suit of suits) {
      for (let rank = 1; rank <= 13; rank++) {
        deck.push({
          id: `${d}_${suit}_${rank}`,
          suit,
          rank,
          deckIndex: d,
          isPhysicalJoker: false,
        });
      }
    }
  }

  // 2 Fiziksel Joker
  deck.push({
    id: '1_J_0',
    suit: 'J',
    rank: 0,
    deckIndex: 1,
    isPhysicalJoker: true,
  });
  deck.push({
    id: '2_J_0',
    suit: 'J',
    rank: 0,
    deckIndex: 2,
    isPhysicalJoker: true,
  });

  return shuffleDeck(deck);
}

/**
 * Fisher-Yates karıştırma algoritması
 */
export function shuffleDeck(deck: Card[]): Card[] {
  const arr = [...deck];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/**
 * Kağıt o elin Jokeri mi? (Fiziksel Joker veya Gösterge kağıdıyla aynı sayı)
 */
export function isWildCard(card: Card, wildRank: number): boolean {
  return card.isPhysicalJoker || (wildRank > 0 && card.rank === wildRank);
}

/**
 * Boşta kalan (per olmamış) kağıdın ceza puanı
 * Sayılar kendi değeri, J/Q/K = 10, As = 11, Boşta kalan Joker = 25
 */
export function getRawCardPenalty(card: Card, wildRank: number): number {
  if (isWildCard(card, wildRank)) {
    return 25;
  }
  if (card.rank === 1) return 11; // As = 11 puan
  if (card.rank >= 11 && card.rank <= 13) return 10; // J, Q, K = 10 puan
  return card.rank; // 2..10 kendi sayı değeri
}

/**
 * Verilen kağıt grubunun (en az 3 kağıt) geçerli bir Per (Grup veya Seri) olup olmadığını kontrol eder.
 * Kurallar:
 * 1) Grup Per (Set): En az 3, en fazla 4 kağıt. Sayılar aynı, semboller FARKLI olmalı.
 * 2) Seri Per (Run): En az 3 kağıt. Semboller AYNI, sayılar ardışık olmalı.
 *    As (1) hem A-2-3 hem Q-K-A olabilir ama Q-K-A-2 (döngüsel) OLAMAZ.
 */
export function isValidMeld(cards: Card[], wildRank: number): boolean {
  if (cards.length < 3) return false;

  const naturals = cards.filter((c) => !isWildCard(c, wildRank));

  // Tümü jokerse (3 veya daha fazla joker kendi başına per oluşturur)
  if (naturals.length === 0) {
    return true;
  }

  // 1. GRUP PER (SET) KONTROLÜ (3 veya 4 kağıt, aynı sayı, FARKLI semboller)
  if (cards.length <= 4) {
    const targetRank = naturals[0].rank;
    const allSameRank = naturals.every((c) => c.rank === targetRank);
    if (allSameRank) {
      const suits = new Set(naturals.map((c) => c.suit));
      // Aynı sembolden iki kağıt aynı grup perde olamaz!
      if (suits.size === naturals.length) {
        return true;
      }
    }
  }

  // 2. SERİ PER (RUN) KONTROLÜ (Aynı sembol, ardışık sayılar, döngüsel olmayan As)
  if (cards.length <= 13) {
    const targetSuit = naturals[0].suit;
    const allSameSuit = naturals.every((c) => c.suit === targetSuit);
    if (!allSameSuit) return false;

    // As olmayan doğal kağıtların sayıları birbirinden farklı olmalı
    const nonAceNaturals = naturals.filter((c) => c.rank !== 1);
    const nonAceRanks = nonAceNaturals.map((c) => c.rank);
    if (new Set(nonAceRanks).size !== nonAceRanks.length) return false;

    const aces = naturals.filter((c) => c.rank === 1);
    // Aynı seride en fazla 1 As anlamlıdır (veya 2 As varsa biri 1 biri 14 ancak 14 kağıtlık seri olamaz)
    if (aces.length > 2) return false;

    // As için olası pozisyon kombinasyonlarını dene (1 veya 14)
    const aceAssignments: number[][] =
      aces.length === 0
        ? [[]]
        : aces.length === 1
        ? [[1], [14]]
        : [[1, 14]];

    const len = cards.length;

    for (const acePos of aceAssignments) {
      const positions = [...nonAceRanks, ...acePos].sort((a, b) => a - b);
      // Aynı pozisyonda iki kağıt olamaz
      if (new Set(positions).size !== positions.length) continue;

      const minPos = positions[0];
      const maxPos = positions[positions.length - 1];

      // Aralarındaki fark toplam kağıt sayısından küçük/eşit olmalı (araları joker doldurur)
      // Ve seri [1..14] aralığında długości len olan bir pencereye sığmalı
      // Dikkat: Pencere [start, start + len - 1] hem 1'i hem 14'ü aynı anda içeremez (len <= 13 olduğu için)
      if (maxPos - minPos < len) {
        const earliestStart = Math.max(1, maxPos - len + 1);
        const latestStart = Math.min(minPos, 14 - len + 1);
        if (earliestStart <= latestStart) {
          return true;
        }
      }
    }
  }

  return false;
}

/**
 * Bir seriyi görsel olarak doğru sıraya (jokerleri boşluklara yerleştirerek) dizer
 */
export function orderMeldCards(cards: Card[], wildRank: number): Card[] {
  const naturals = cards.filter((c) => !isWildCard(c, wildRank));
  const wilds = cards.filter((c) => isWildCard(c, wildRank));
  if (naturals.length <= 1) return [...naturals, ...wilds];

  // Grup per ise
  if (naturals.every((c) => c.rank === naturals[0].rank)) {
    return [...naturals, ...wilds];
  }

  // Seri per ise As'ın 1 mi 14 mü olduğunu bul
  const hasHighCards = naturals.some((c) => c.rank >= 10);
  const mapped = naturals
    .map((c) => ({
      card: c,
      pos: c.rank === 1 && hasHighCards ? 14 : c.rank,
    }))
    .sort((a, b) => a.pos - b.pos);

  const result: Card[] = [];
  const usedWilds = [...wilds];

  for (let i = 0; i < mapped.length; i++) {
    if (i > 0) {
      const gap = mapped[i].pos - mapped[i - 1].pos - 1;
      for (let g = 0; g < gap && usedWilds.length > 0; g++) {
        result.push(usedWilds.pop()!);
      }
    }
    result.push(mapped[i].card);
  }

  while (usedWilds.length > 0) {
    result.push(usedWilds.pop()!);
  }
  return result;
}

/**
 * Oyuncunun elindeki kağıtları (10 veya 11 kağıt) analiz ederek:
 * - En düşük ceza puanını bırakan optimum perleri bulur
 * - Eldeki Joker bir pere dahil olabiliyorsa 0 puan sayar, hiçbir pere giremiyorsa 25 puan yazar
 * - Tüm kağıtlar per oluyorsa canFinish = true döner
 */
export function evaluateHandOptimal(cards: Card[], wildRank: number): HandEvaluation {
  const n = cards.length;
  if (n === 0) {
    return { canFinish: true, melds: [], unmelded: [], penalty: 0, orderedCards: [] };
  }

  // 1. Eldeki kağıtlardan oluşturulabilecek tüm geçerli perleri (bitmask olarak) üret
  interface CandidateMeld {
    mask: number;
    cards: Card[];
  }
  const validMelds: CandidateMeld[] = [];

  const totalMasks = 1 << n;
  for (let mask = 0; mask < totalMasks; mask++) {
    // Bit sayısını hesapla (3 ile n arası)
    let bitCount = 0;
    let temp = mask;
    while (temp > 0) {
      bitCount += temp & 1;
      temp >>= 1;
    }
    if (bitCount < 3 || bitCount > 10) continue;

    const subset: Card[] = [];
    for (let i = 0; i < n; i++) {
      if ((mask & (1 << i)) !== 0) {
        subset.push(cards[i]);
      }
    }

    if (isValidMeld(subset, wildRank)) {
      validMelds.push({ mask, cards: subset });
    }
  }

  // 2. Backtracking ile kesişmeyen per kombinasyonlarını dene ve en düşük cezayı bul
  let bestPenalty = Infinity;
  let bestMeldMasks: number[] = [];
  let bestMeldedCardCount = -1;

  // Başlangıçta hiç per yapılmamış durumu hesapla
  const rawPenalties = cards.map((c) => getRawCardPenalty(c, wildRank));

  function computeUnmeldedPenalty(usedMask: number): { penalty: number; meldedCount: number } {
    let penalty = 0;
    let meldedCount = 0;
    for (let i = 0; i < n; i++) {
      if ((usedMask & (1 << i)) === 0) {
        penalty += rawPenalties[i];
      } else {
        meldedCount++;
      }
    }
    return { penalty, meldedCount };
  }

  const visitedMasks = new Set<number>();

  function search(usedMask: number, startIdx: number, currentMasks: number[]) {
    if (visitedMasks.has(usedMask)) return;
    visitedMasks.add(usedMask);

    const { penalty, meldedCount } = computeUnmeldedPenalty(usedMask);
    if (
      penalty < bestPenalty ||
      (penalty === bestPenalty && meldedCount > bestMeldedCardCount)
    ) {
      bestPenalty = penalty;
      bestMeldMasks = [...currentMasks];
      bestMeldedCardCount = meldedCount;
    }

    if (bestPenalty === 0 && bestMeldedCardCount === n) return;

    for (let i = startIdx; i < validMelds.length; i++) {
      const m = validMelds[i];
      if ((usedMask & m.mask) === 0) {
        currentMasks.push(m.mask);
        search(usedMask | m.mask, i + 1, currentMasks);
        currentMasks.pop();
      }
    }
  }

  search(0, 0, []);

  // Optimum perleri ve boşta kalan kağıtları çıkart
  let finalUsedMask = 0;
  const chosenMelds: Card[][] = [];
  for (const mMask of bestMeldMasks) {
    finalUsedMask |= mMask;
    const meldCards: Card[] = [];
    for (let i = 0; i < n; i++) {
      if ((mMask & (1 << i)) !== 0) {
        meldCards.push(cards[i]);
      }
    }
    chosenMelds.push(orderMeldCards(meldCards, wildRank));
  }

  const unmelded: Card[] = [];
  for (let i = 0; i < n; i++) {
    if ((finalUsedMask & (1 << i)) === 0) {
      unmelded.push(cards[i]);
    }
  }

  // Boşta kalan kağıtları sembol ve sayıya göre sırala
  const suitOrder: Record<Suit, number> = { S: 1, H: 2, C: 3, D: 4, J: 5 };
  unmelded.sort((a, b) => {
    const aWild = isWildCard(a, wildRank) ? 1 : 0;
    const bWild = isWildCard(b, wildRank) ? 1 : 0;
    if (aWild !== bWild) return aWild - bWild;
    if (suitOrder[a.suit] !== suitOrder[b.suit]) return suitOrder[a.suit] - suitOrder[b.suit];
    return a.rank - b.rank;
  });

  const orderedCards = [...chosenMelds.flat(), ...unmelded];

  return {
    canFinish: unmelded.length === 0 && n === 10,
    melds: chosenMelds,
    unmelded,
    penalty: bestPenalty,
    orderedCards,
  };
}

/**
 * 11 kağıtlı bir elde oyuncunun hangi kağıdı atarsa elini açıp bitirebileceğini kontrol eder.
 * Eğer bitebiliyorsa atılacak kağıdı ve kalan 10 kağıdın perlerini döner.
 */
export function findWinningDiscard(
  cards11: Card[],
  wildRank: number
): { canWin: boolean; discardCard?: Card; evaluation?: HandEvaluation } {
  if (cards11.length !== 11) return { canWin: false };

  for (let i = 0; i < cards11.length; i++) {
    const remaining10 = cards11.filter((_, idx) => idx !== i);
    const eval10 = evaluateHandOptimal(remaining10, wildRank);
    if (eval10.canFinish) {
      return {
        canWin: true,
        discardCard: cards11[i],
        evaluation: eval10,
      };
    }
  }
  return { canWin: false };
}

/**
 * 30 saniye hamle süresi dolduğunda:
 * Eldeki 11 kağıt içinden PER OLMAYAN ve JOKER OLMAYAN en büyük (en yüksek ceza puanlı) gereksiz kağıdı seçer.
 */
export function selectBestAutoDiscard(cards11: Card[], wildRank: number): Card {
  const eval11 = evaluateHandOptimal(cards11, wildRank);

  // 1. Öncelik: Boşta kalan (unmelded) ve Joker OLMAYAN kağıtlar içinden en yüksek puanlı olanı at
  const nonWildUnmelded = eval11.unmelded.filter((c) => !isWildCard(c, wildRank));
  if (nonWildUnmelded.length > 0) {
    nonWildUnmelded.sort(
      (a, b) => getRawCardPenalty(b, wildRank) - getRawCardPenalty(a, wildRank)
    );
    return nonWildUnmelded[0];
  }

  // 2. Öncelik: Tüm boşta kalanlar jokerse veya tüm kağıtlar perdeyse,
  // Joker olmayan kağıtlar arasından atıldığında kalan 10 kağıtta en az cezayı bırakan en büyük kağıdı seç
  const nonWildAll = cards11.filter((c) => !isWildCard(c, wildRank));
  if (nonWildAll.length > 0) {
    let bestCandidate = nonWildAll[0];
    let bestRemainingPenalty = Infinity;
    let bestCandidateValue = -1;

    for (const candidate of nonWildAll) {
      const rem10 = cards11.filter((c) => c.id !== candidate.id);
      const remEval = evaluateHandOptimal(rem10, wildRank);
      const candVal = getRawCardPenalty(candidate, wildRank);
      if (
        remEval.penalty < bestRemainingPenalty ||
        (remEval.penalty === bestRemainingPenalty && candVal > bestCandidateValue)
      ) {
        bestRemainingPenalty = remEval.penalty;
        bestCandidateValue = candVal;
        bestCandidate = candidate;
      }
    }
    return bestCandidate;
  }

  // 3. Çok nadir durum: Eldeki 11 kağıdın tamamı jokerse ilkini at
  return cards11[0];
}

/**
 * Dağıtım: Aktif oyunculara 2'şer 2'şer toplam 10'ar kağıt dağıtır.
 * Kalan destenin en üstündeki (joker olmayan) kağıdı ters çevirip en alta yarısı görünür Gösterge Jokeri olarak koyar.
 */
export function dealRoundHands(playerIds: string[]): {
  hands: Record<string, Card[]>;
  drawPile: Card[];
  indicatorCard: Card;
  wildRank: number;
} {
  const deck = createDeck();
  const hands: Record<string, Card[]> = {};
  for (const pid of playerIds) {
    hands[pid] = [];
  }

  // 2'şer 2'şer 5 turda toplam 10'ar kağıt dağıt
  let deckCursor = 0;
  for (let pass = 0; pass < 5; pass++) {
    for (const pid of playerIds) {
      hands[pid].push(deck[deckCursor++], deck[deckCursor++]);
    }
  }

  const remaining = deck.slice(deckCursor);

  // En üstteki fiziksel joker olmayan kağıdı Gösterge olarak seç
  let indicatorIdx = remaining.findIndex((c) => !c.isPhysicalJoker);
  if (indicatorIdx === -1) indicatorIdx = 0;

  const [indicatorCard] = remaining.splice(indicatorIdx, 1);
  const wildRank = indicatorCard.rank;

  // Gösterge kağıdı destenin en altına (son çekilecek kağıt olarak) yarısı görünür şekilde yerleştirilir
  const drawPile = [...remaining, indicatorCard];

  return {
    hands,
    drawPile,
    indicatorCard,
    wildRank,
  };
}
