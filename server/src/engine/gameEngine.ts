import crypto from 'crypto';

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
    const j = crypto.randomInt(0, i + 1);
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
 * Bir seriyi görsel olarak doğru sıraya (jokerleri boşluklara yerleştirerek) dizer.
 * Eğer oyuncu kağıtları zaten geçerli bir seri sırasıyla dizmişse (ör. 2♠ - Joker - Joker - 5♠),
 * oyuncunun kendi dizilim sırasını birebir korur.
 */
export function orderMeldCards(cards: Card[], wildRank: number): Card[] {
  const naturals = cards.filter((c) => !isWildCard(c, wildRank));
  const wilds = cards.filter((c) => isWildCard(c, wildRank));
  if (naturals.length <= 1) return [...cards];

  // Grup per ise (aynı sayı farklı renkler)
  if (naturals.every((c) => c.rank === naturals[0].rank)) {
    return [...naturals, ...wilds];
  }

  // Oyuncunun mevcut dizilimi zaten geçerli bir ardışık sıra mı kontrol et
  for (const aceAs14 of [false, true]) {
    let matchesExistingOrder = true;
    let impliedStart: number | null = null;
    for (let i = 0; i < cards.length; i++) {
      const c = cards[i];
      if (!isWildCard(c, wildRank)) {
        const pos = c.rank === 1 && aceAs14 ? 14 : c.rank;
        const startCandidate = pos - i;
        if (impliedStart === null) {
          impliedStart = startCandidate;
        } else if (impliedStart !== startCandidate) {
          matchesExistingOrder = false;
          break;
        }
      }
    }
    if (
      matchesExistingOrder &&
      impliedStart !== null &&
      impliedStart >= 1 &&
      impliedStart + cards.length - 1 <= 14
    ) {
      return [...cards];
    }
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
        result.push(usedWilds.shift()!);
      }
    }
    result.push(mapped[i].card);
  }

  // Kalan jokerleri serinin üstüne (14'ü geçmiyorsa) veya altına ekle
  let currentMaxPos = mapped[mapped.length - 1].pos;
  while (usedWilds.length > 0) {
    if (currentMaxPos < 14) {
      result.push(usedWilds.shift()!);
      currentMaxPos++;
    } else {
      result.unshift(usedWilds.shift()!);
    }
  }
  return result;
}

/**
 * Oyuncunun elindeki kağıtları (10 veya 11 kağıt) analiz ederek:
 * - 10 kağıtlık tam bitiş (0 ceza / 11 kağıtta 1 kağıt atarak bitiş) varsa HER ZAMAN onu birinci öncelik yapar!
 *   (Böylece 2♠ - Joker - Joker - 5♠ + Papaz varken, Papaz 10 puan diye Jokerleri Papaz'ın yanına ASLA koymaz!)
 * - Tam bitiş yoksa en düşük ceza puanını bırakan optimum perleri bulur.
 */
export function evaluateHandOptimal(cards: Card[], wildRank: number): HandEvaluation {
  const n = cards.length;
  if (n === 0) {
    return { canFinish: true, melds: [], unmelded: [], penalty: 0, orderedCards: [] };
  }

  // 1. Eldeki kağıtlardan oluşturulabilecek tüm geçerli perleri (bitmask olarak) üret
  interface CandidateMeld {
    mask: number;
    bitCount: number;
    cards: Card[];
  }
  const validMelds: CandidateMeld[] = [];

  const totalMasks = 1 << n;
  for (let mask = 0; mask < totalMasks; mask++) {
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
      validMelds.push({ mask, bitCount, cards: subset });
    }
  }

  // Büyük perleri önce dene
  validMelds.sort((a, b) => b.bitCount - a.bitCount);

  const rawPenalties = cards.map((c) => getRawCardPenalty(c, wildRank));

  let bestIsFinishReady = false; // 10 kağıt per olmuş mu? (n=10'da 10 kağıt, n=11'de >=10 kağıt)
  let bestPenalty = Infinity;
  let bestMeldMasks: number[] = [];
  let bestMeldedCardCount = -1;
  let bestDiscardCandidateValue = -1; // n=11'de 10 kağıt per olduğunda atılacak 11. kağıdın puanı (yüksek olanı atmak avantajlıdır)

  function evaluateMaskState(usedMask: number): {
    isFinishReady: boolean;
    penalty: number;
    meldedCount: number;
    discardCandidateValue: number;
  } {
    let penalty = 0;
    let meldedCount = 0;
    let singleUnmeldedVal = -1;
    for (let i = 0; i < n; i++) {
      if ((usedMask & (1 << i)) === 0) {
        penalty += rawPenalties[i];
        singleUnmeldedVal = isWildCard(cards[i], wildRank) ? 0 : rawPenalties[i];
      } else {
        meldedCount++;
      }
    }
    const isFinishReady =
      (n === 10 && meldedCount === 10) || (n === 11 && meldedCount === 10);
    return {
      isFinishReady,
      penalty: isFinishReady && n === 10 ? 0 : penalty,
      meldedCount,
      discardCandidateValue: n === 11 && meldedCount === 10 ? singleUnmeldedVal : -1,
    };
  }

  // Aynı usedMask'a daha erken bir startIdx ile ulaşıldıysa tekrar arama yapmaya gerek yok
  const minStartIdxByMask = new Map<number, number>();

  function search(usedMask: number, startIdx: number, currentMasks: number[]) {
    const prevStart = minStartIdxByMask.get(usedMask);
    if (prevStart !== undefined && prevStart <= startIdx) return;
    minStartIdxByMask.set(usedMask, startIdx);

    const state = evaluateMaskState(usedMask);

    let isBetter = false;
    if (state.isFinishReady && !bestIsFinishReady) {
      isBetter = true;
    } else if (state.isFinishReady && bestIsFinishReady) {
      if (state.discardCandidateValue > bestDiscardCandidateValue) {
        isBetter = true;
      }
    } else if (!state.isFinishReady && !bestIsFinishReady) {
      if (
        state.penalty < bestPenalty ||
        (state.penalty === bestPenalty && state.meldedCount > bestMeldedCardCount)
      ) {
        isBetter = true;
      }
    }

    if (isBetter) {
      bestIsFinishReady = state.isFinishReady;
      bestPenalty = state.penalty;
      bestMeldMasks = [...currentMasks];
      bestMeldedCardCount = state.meldedCount;
      bestDiscardCandidateValue = state.discardCandidateValue;
    }

    if (n === 10 && bestIsFinishReady) return;

    for (let i = startIdx; i < validMelds.length; i++) {
      const m = validMelds[i];
      if ((usedMask & m.mask) === 0) {
        // 11 kağıtlı elde 10 kağıttan fazlası (11 kağıt) tek seferde açılmaz (1 kağıt yere atılmalıdır)
        if (n === 11 && state.meldedCount + m.bitCount > 10) continue;
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
    penalty: bestIsFinishReady ? 0 : bestPenalty,
    orderedCards,
  };
}

/**
 * Bir satırdaki kağıtların (tek bir per veya yan yana konulmuş iki per olarak)
 * tamamının geçerli per oluşturup oluşturmadığını kontrol eder ve oyuncunun sırasını koruyarak döner.
 */
export function decomposeRowIntoMelds(
  rowCards: Card[],
  wildRank: number
): { valid: boolean; melds: Card[][] } {
  const len = rowCards.length;
  if (len === 0) return { valid: true, melds: [] };
  if (len < 3) return { valid: false, melds: [] };

  // 1. Satırın tamamı tek başına geçerli bir per mi? (Ör: 2♠ - Joker - Joker - 5♠)
  if (isValidMeld(rowCards, wildRank)) {
    return { valid: true, melds: [orderMeldCards(rowCards, wildRank)] };
  }

  // 2. Satırda yan yana dizilmiş 2 (veya 3) bitişik per var mı? (Ör: 3'lü per + 3'lü per aynı satırda)
  if (len >= 6) {
    for (let split1 = 3; split1 <= len - 3; split1++) {
      const firstPart = rowCards.slice(0, split1);
      const restPart = rowCards.slice(split1);
      if (isValidMeld(firstPart, wildRank)) {
        const sub = decomposeRowIntoMelds(restPart, wildRank);
        if (sub.valid) {
          return {
            valid: true,
            melds: [orderMeldCards(firstPart, wildRank), ...sub.melds],
          };
        }
      }
    }
  }

  // 3. Satır içindeki kağıtlar kendi içinde firesiz per oluyor mu?
  const rowEval = evaluateHandOptimal(rowCards, wildRank);
  if (rowEval.unmelded.length === 0 && rowEval.melds.flat().length === len) {
    return { valid: true, melds: rowEval.melds };
  }

  return { valid: false, melds: [] };
}

/**
 * Oyuncunun 3 sıraya dizdiği 11 kağıt içinde, 1 kağıt yere atıldığında kalan 10 kağıdın
 * oyuncunun kendi 3 sıra diziliminde geçerli perler oluşturup oluşturmadığını kontrol eder.
 * Böylece oyuncunun yaptığı 2♠ - Joker - Joker - 5♠ perini ASLA bozmaz ve dışarıdaki 11. kağıdı (ör. Papaz) atar!
 */
export function evaluatePlayerRowsForFinish(
  hand11: Card[],
  handRows: string[][] | undefined,
  wildRank: number,
  preferredDiscardCardId?: string
): {
  canWinFromRows: boolean;
  discardCard?: Card;
  melds?: Card[][];
  orderedCards?: Card[];
} {
  if (hand11.length !== 11 || !handRows || handRows.length !== 3) {
    return { canWinFromRows: false };
  }

  const cardMap = new Map(hand11.map((c) => [c.id, c]));

  // Denenecek atılacak kağıt adaylarını sırala:
  // 1. Kullanıcının seçtiği kağıt (varsa)
  // 2. Bir satırda tek başına duran kağıtlar veya satır başı/sonundaki yüksek cezalı kağıtlar
  const candidateDiscardIds: string[] = [];
  if (preferredDiscardCardId && cardMap.has(preferredDiscardCardId)) {
    candidateDiscardIds.push(preferredDiscardCardId);
  }
  for (const c of hand11) {
    if (!candidateDiscardIds.includes(c.id)) {
      candidateDiscardIds.push(c.id);
    }
  }

  for (const candId of candidateDiscardIds) {
    const discardCard = cardMap.get(candId);
    if (!discardCard) continue;

    let allRowsValid = true;
    const collectedMelds: Card[][] = [];
    let totalCardsInRows = 0;

    for (let r = 0; r < 3; r++) {
      const rowIds = (handRows[r] || []).filter((id) => id !== candId);
      const rowCards = rowIds
        .map((id) => cardMap.get(id))
        .filter((c): c is Card => c !== undefined);

      if (rowCards.length === 0) continue;
      totalCardsInRows += rowCards.length;

      const decomp = decomposeRowIntoMelds(rowCards, wildRank);
      if (!decomp.valid) {
        allRowsValid = false;
        break;
      }
      collectedMelds.push(...decomp.melds);
    }

    if (allRowsValid && totalCardsInRows === 10) {
      return {
        canWinFromRows: true,
        discardCard,
        melds: collectedMelds,
        orderedCards: collectedMelds.flat(),
      };
    }
  }

  return { canWinFromRows: false };
}

/**
 * 11 kağıtlı bir elde oyuncunun hangi kağıdı atarsa elini açıp bitirebileceğini kontrol eder.
 * Önce oyuncunun kendi 3 sıra dizilimini (`handRows`) kontrol eder; orada geçerli bir 10'lu per dizilimi varsa
 * (örneğin 2♠ - Joker - Joker - 5♠ ve boşta Papaz) doğrudan onu kullanır!
 */
export function findWinningDiscard(
  cards11: Card[],
  wildRank: number,
  handRows?: string[][],
  preferredDiscardCardId?: string
): { canWin: boolean; discardCard?: Card; evaluation?: HandEvaluation } {
  if (cards11.length !== 11) return { canWin: false };

  // 1. ÖNCE oyuncunun kendi 3 sıra diziliminde geçerli bitiş var mı bak!
  if (handRows && handRows.length === 3) {
    const rowWin = evaluatePlayerRowsForFinish(
      cards11,
      handRows,
      wildRank,
      preferredDiscardCardId
    );
    if (rowWin.canWinFromRows && rowWin.discardCard && rowWin.melds && rowWin.orderedCards) {
      return {
        canWin: true,
        discardCard: rowWin.discardCard,
        evaluation: {
          canFinish: true,
          melds: rowWin.melds,
          unmelded: [],
          penalty: 0,
          orderedCards: rowWin.orderedCards,
        },
      };
    }
  }

  // 2. Genel kombinasyon taraması (Joker olmayan yüksek puanlı kağıdı atmayı tercih et)
  let bestResult: { canWin: boolean; discardCard?: Card; evaluation?: HandEvaluation } = {
    canWin: false,
  };
  let bestDiscardScore = -1;

  for (let i = 0; i < cards11.length; i++) {
    const cand = cards11[i];
    const remaining10 = cards11.filter((_, idx) => idx !== i);
    const eval10 = evaluateHandOptimal(remaining10, wildRank);
    if (eval10.canFinish) {
      const score =
        (preferredDiscardCardId && cand.id === preferredDiscardCardId ? 1000 : 0) +
        (isWildCard(cand, wildRank) ? 0 : getRawCardPenalty(cand, wildRank));
      if (score > bestDiscardScore) {
        bestDiscardScore = score;
        bestResult = {
          canWin: true,
          discardCard: cand,
          evaluation: eval10,
        };
      }
    }
  }
  return bestResult;
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
