import { Suspense } from 'react';
import Explorer from '@/components/Explorer';

export const metadata = { title: 'Backtest explorer · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Explorer /></Suspense>;
}
