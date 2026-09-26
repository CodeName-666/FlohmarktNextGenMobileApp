import '../domain/models.dart';

const demoPayload = 'MM1|092700104200054|1|6BCD8E44';
const demoMarketId = 'demo-market';
const demoCatalog = [
  ArticleListing(
    listingId: 'demo-listing-1',
    articleId: 'demo-article-1',
    codeFull: '092700104200054',
    title: 'Kinderbuch · Waldabenteuer',
    priceCents: 250,
    labelRevision: 1,
    exportGeneration: 1,
    boxNumber: 7,
    marketId: demoMarketId,
  ),
  ArticleListing(
    listingId: 'demo-listing-2',
    articleId: 'demo-article-2',
    codeFull: '092700104200062',
    title: 'Regenjacke · Größe 104',
    priceCents: 650,
    labelRevision: 1,
    exportGeneration: 1,
    boxNumber: 7,
    marketId: demoMarketId,
  ),
];
