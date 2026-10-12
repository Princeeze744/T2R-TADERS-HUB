import { Suspense } from 'react';
import Watchlist from '@/components/Watchlist';

export const metadata = { title: 'Watchlist · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Watchlist /></Suspense>;
}
