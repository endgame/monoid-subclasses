{-
    Copyright 2014-2021 Mario Blazevic

    License: BSD3 (see BSD3-LICENSE.txt file)
-}

-- | This module defines two monoid transformer data types, 'OffsetPositioned' and 'LinePositioned'. Both data types add
-- a notion of the current position to their base monoid. In case of 'OffsetPositioned', the current position is a
-- simple integer offset from the beginning of the monoid, and it can be applied to any 'StableFactorial'. The
-- base monoid of 'LinePositioned' must be a 'TextualMonoid', but for the price it will keep track of the current line
-- and column numbers as well.
--
-- Line number is zero-based, column one-based:
--
-- >> let p = pure "abcd\nefgh\nijkl\nmnop\n" :: LinePositioned String
-- >> p
-- >"abcd\nefgh\nijkl\nmnop\n"
-- >> Data.Monoid.Factorial.drop 13 p
-- >Line 2, column 4: "l\nmnop\n"

{-# LANGUAGE Haskell2010 #-}

module Data.Monoid.Instances.Positioned (
   OffsetPositioned, LinePositioned, extract, position, line, column
   )
where

import Control.Applicative -- (Applicative(..))
import qualified Data.List as List
import Data.String (IsString(..))

import Data.Semigroup (Semigroup(..))
import Data.Monoid (Monoid(..), Endo(..))
import Data.Semigroup.Cancellative (LeftReductive(..), RightReductive(..))
import Data.Semigroup.Factorial (Factorial(..), StableFactorial)
import Data.Monoid.GCD (LeftGCDMonoid(..), RightGCDMonoid(..))
import Data.Monoid.Null (MonoidNull(null), PositiveMonoid)
import Data.Monoid.Factorial (FactorialMonoid(..))
import Data.Monoid.Textual (TextualMonoid(..))
import qualified Data.Semigroup.Factorial as Factorial
import qualified Data.Monoid.Factorial as Factorial
import qualified Data.Monoid.Textual as Textual

import Prelude hiding (all, any, break, filter, foldl, foldl1, foldr, foldr1, lines, map, concatMap,
                       length, null, reverse, scanl, scanr, scanl1, scanr1, span, splitAt)

class Positioned p where
   extract :: p a -> a
   position :: p a -> Int

data OffsetPositioned m = OffsetPositioned{offset :: !Int,
                                           -- ^ the current offset
                                           extractOffset :: m}

data LinePositioned m = LinePositioned{fullOffset :: !Int,
                                       -- | the current line
                                       line :: !Int,
                                       lineStart :: !Int,
                                       extractLines :: m}

-- | the current column
column :: LinePositioned m -> Int
column lp = position lp - lineStart lp

instance Functor OffsetPositioned where
   fmap f (OffsetPositioned p c) = OffsetPositioned p (f c)

instance Functor LinePositioned where
   fmap f (LinePositioned p l lp c) = LinePositioned p l lp (f c)

instance Applicative OffsetPositioned where
   pure = OffsetPositioned 0
   OffsetPositioned _ f <*> OffsetPositioned p c = OffsetPositioned p (f c)

instance Applicative LinePositioned where
   pure = LinePositioned 0 0 (-1)
   LinePositioned _ _ _ f <*> LinePositioned p l lp c = LinePositioned p l lp (f c)

instance Positioned OffsetPositioned where
   extract = extractOffset
   position = offset

instance Positioned LinePositioned where
   extract = extractLines
   position = fullOffset

instance Eq m => Eq (OffsetPositioned m) where
   OffsetPositioned{extractOffset= a} == OffsetPositioned{extractOffset= b} = a == b

instance Eq m => Eq (LinePositioned m) where
   LinePositioned{extractLines= a} == LinePositioned{extractLines= b} = a == b

instance Ord m => Ord (OffsetPositioned m) where
   compare OffsetPositioned{extractOffset= a} OffsetPositioned{extractOffset= b} = compare a b

instance Ord m => Ord (LinePositioned m) where
   compare LinePositioned{extractLines= a} LinePositioned{extractLines= b} = compare a b

instance Show m => Show (OffsetPositioned m) where
   showsPrec prec (OffsetPositioned 0 c) = showsPrec prec c
   showsPrec prec (OffsetPositioned pos c) = shows pos . (": " ++) . showsPrec prec c

instance Show m => Show (LinePositioned m) where
   showsPrec prec (LinePositioned 0 0 (-1) c) = showsPrec prec c
   showsPrec prec (LinePositioned pos l lpos c) =
      ("Line " ++) . shows l . (", column " ++) . shows (pos - lpos) . (": " ++) . showsPrec prec c

instance StableFactorial m => Semigroup (OffsetPositioned m) where
   OffsetPositioned p1 c1 <> OffsetPositioned p2 c2 =
      OffsetPositioned (if p1 /= 0 || p2 == 0 then p1 else max 0 $ p2 - length c1) (c1 <> c2)
   {-# INLINE (<>) #-}

instance (FactorialMonoid m, StableFactorial m) => Monoid (OffsetPositioned m) where
   mempty = pure mempty
   mappend = (<>)
   {-# INLINE mempty #-}
   {-# INLINE mappend #-}

instance (StableFactorial m, TextualMonoid m) => Semigroup (LinePositioned m) where
   LinePositioned p1 l1 lp1 c1 <> LinePositioned p2 l2 lp2 c2
     | p1 /= 0 || p2 == 0 = LinePositioned p1 l1 lp1 c
     | otherwise = LinePositioned p2' l2' lp2' c
     where c = mappend c1 c2
           p2' = max 0 $ p2 - length c1
           lp2' = p2' - (p2 - lp2 - cd + 1)
           l2' = if l2 == 0 then 0 else max 0 (l2 - ld)
           (ld, cd) = linesColumns' c1
   {-# INLINE (<>) #-}

instance (StableFactorial m, TextualMonoid m) => Monoid (LinePositioned m) where
   mempty = pure mempty
   mappend = (<>)
   {-# INLINE mempty #-}

instance (StableFactorial m, FactorialMonoid m) => MonoidNull (OffsetPositioned m) where
   null = null . extractOffset
   {-# INLINE null #-}

instance (StableFactorial m, TextualMonoid m, MonoidNull m) => MonoidNull (LinePositioned m) where
   null = null . extractLines
   {-# INLINE null #-}

instance (StableFactorial m, FactorialMonoid m) => PositiveMonoid (OffsetPositioned m)

instance (StableFactorial m, TextualMonoid m) => PositiveMonoid (LinePositioned m)

instance (StableFactorial m, LeftReductive m) => LeftReductive (OffsetPositioned m) where
   isPrefixOf (OffsetPositioned _ c1) (OffsetPositioned _ c2) = isPrefixOf c1 c2
   stripPrefix (OffsetPositioned _ c1) (OffsetPositioned p c2) = fmap (OffsetPositioned (p + length c1)) (stripPrefix c1 c2)
   {-# INLINE isPrefixOf #-}
   {-# INLINE stripPrefix #-}

instance (StableFactorial m, TextualMonoid m) => LeftReductive (LinePositioned m) where
   isPrefixOf a b = isPrefixOf (extractLines a) (extractLines b)
   stripPrefix LinePositioned{extractLines= c1} (LinePositioned p l lpos c2) =
      let (lines, columns) = linesColumns' c1
          len = length c1
      in fmap (LinePositioned (p + len) (l + lines) (lpos + len - columns)) (stripPrefix c1 c2)
   {-# INLINE isPrefixOf #-}
   {-# INLINE stripPrefix #-}

instance (StableFactorial m, FactorialMonoid m, LeftGCDMonoid m) => LeftGCDMonoid (OffsetPositioned m) where
   commonPrefix (OffsetPositioned p1 c1) (OffsetPositioned p2 c2) = OffsetPositioned (min p1 p2) (commonPrefix c1 c2)
   stripCommonPrefix (OffsetPositioned p1 c1) (OffsetPositioned p2 c2) =
      (OffsetPositioned (min p1 p2) prefix, OffsetPositioned (p1 + l) c1', OffsetPositioned (p2 + l) c2')
      where (prefix, c1', c2') = stripCommonPrefix c1 c2
            l = length prefix
   {-# INLINE commonPrefix #-}
   {-# INLINE stripCommonPrefix #-}

instance (StableFactorial m, TextualMonoid m, LeftGCDMonoid m) => LeftGCDMonoid (LinePositioned m) where
   commonPrefix (LinePositioned p1 l1 lp1 c1) (LinePositioned p2 l2 lp2 c2) =
      if p1 <= p2
      then LinePositioned p1 l1 lp1 (commonPrefix c1 c2)
      else LinePositioned p2 l2 lp2 (commonPrefix c1 c2)
   stripCommonPrefix (LinePositioned p1 l1 lp1 c1) (LinePositioned p2 l2 lp2 c2) =
      let (prefix, c1', c2') = stripCommonPrefix c1 c2
          (lines, columns) = linesColumns' prefix
          len = length prefix
      in (if p1 <= p2 then LinePositioned p1 l1 lp1 prefix else LinePositioned p2 l2 lp2 prefix,
          LinePositioned (p1 + len) (l1 + lines) (lp1 + len - columns) c1',
          LinePositioned (p2 + len) (l2 + lines) (lp2 + len - columns) c2')
   {-# INLINE commonPrefix #-}
   {-# INLINE stripCommonPrefix #-}

instance (StableFactorial m, FactorialMonoid m, RightReductive m) => RightReductive (OffsetPositioned m) where
   isSuffixOf (OffsetPositioned _ c1) (OffsetPositioned _ c2) = isSuffixOf c1 c2
   stripSuffix (OffsetPositioned _ c1) (OffsetPositioned p c2) = fmap (OffsetPositioned p) (stripSuffix c1 c2)
   {-# INLINE isSuffixOf #-}
   {-# INLINE stripSuffix #-}

instance (StableFactorial m, TextualMonoid m, RightReductive m) => RightReductive (LinePositioned m) where
   isSuffixOf LinePositioned{extractLines=c1} LinePositioned{extractLines=c2} = isSuffixOf c1 c2
   stripSuffix (LinePositioned p l lp c1) LinePositioned{extractLines=c2} =
      fmap (LinePositioned p l lp) (stripSuffix c1 c2)
   {-# INLINE isSuffixOf #-}
   {-# INLINE stripSuffix #-}

instance (StableFactorial m, FactorialMonoid m, RightGCDMonoid m) => RightGCDMonoid (OffsetPositioned m) where
   commonSuffix (OffsetPositioned p1 c1) (OffsetPositioned p2 c2) =
      OffsetPositioned (min (p1 + length c1) (p2 + length c2) - length suffix) suffix
      where suffix = commonSuffix c1 c2
   stripCommonSuffix (OffsetPositioned p1 c1) (OffsetPositioned p2 c2) =
      (OffsetPositioned p1 c1', OffsetPositioned p2 c2',
       OffsetPositioned (min (p1 + length c1') (p2 + length c2')) suffix)
      where (c1', c2', suffix) = stripCommonSuffix c1 c2
   {-# INLINE commonSuffix #-}
   {-# INLINE stripCommonSuffix #-}

instance (StableFactorial m, TextualMonoid m, RightGCDMonoid m) => RightGCDMonoid (LinePositioned m) where
   stripCommonSuffix (LinePositioned p1 l1 lp1 c1) (LinePositioned p2 l2 lp2 c2) =
      (LinePositioned p1 l1 lp1 c1', LinePositioned p2 l2 lp2 c2',
       if p1 < p2
       then LinePositioned (p1 + len1) (l1 + lines1) (lp1 + len1 - columns1) suffix
       else LinePositioned (p2 + len2) (l2 + lines2) (lp2 + len2 - columns2) suffix)
      where (c1', c2', suffix) = stripCommonSuffix c1 c2
            len1 = length c1'
            len2 = length c2'
            (lines1, columns1) = linesColumns' c1'
            (lines2, columns2) = linesColumns' c2'

instance StableFactorial m => Factorial (OffsetPositioned m) where
   factors (OffsetPositioned p c) = snd $ List.mapAccumL next p (factors c)
      where next p1 c1 = (succ p1, OffsetPositioned p1 c1)
   primePrefix (OffsetPositioned p c) = OffsetPositioned p (primePrefix c)
   foldl f a0 (OffsetPositioned p0 c0) = fst $ Factorial.foldl f' (a0, p0) c0
      where f' (a, p) c = (f a (OffsetPositioned p c), succ p)
   foldl' f a0 (OffsetPositioned p0 c0) = fst $ Factorial.foldl' f' (a0, p0) c0
      where f' (a, p) c = let a' = f a (OffsetPositioned p c) in seq a' (a', succ p)
   foldr f a0 (OffsetPositioned p0 c0) = Factorial.foldr f' (const a0) c0 p0
      where f' c cont p = f (OffsetPositioned p c) (cont $! succ p)
   foldMap f (OffsetPositioned p c) = appEndo (Factorial.foldMap f' c) (const mempty) p
      where -- f' :: m -> Endo (Int -> m)
            f' prime = Endo (\cont pos-> f (OffsetPositioned pos prime) `mappend` cont (succ pos))
   length (OffsetPositioned _ c) = length c
   reverse (OffsetPositioned p c) = OffsetPositioned p (Factorial.reverse c)
   {-# INLINE primePrefix #-}
   {-# INLINE foldl #-}
   {-# INLINE foldl' #-}
   {-# INLINE foldr #-}
   {-# INLINE foldMap #-}

instance (StableFactorial m, FactorialMonoid m) => FactorialMonoid (OffsetPositioned m) where
   splitPrimePrefix (OffsetPositioned p c) = fmap rewrap (splitPrimePrefix c)
      where rewrap (cp, cs) = (OffsetPositioned p cp, OffsetPositioned (if null cs then 0 else succ p) cs)
   splitPrimeSuffix (OffsetPositioned p c) = fmap rewrap (splitPrimeSuffix c)
      where rewrap (cp, cs) = (OffsetPositioned p cp, OffsetPositioned (p + length cp) cs)
   spanMaybe s0 f (OffsetPositioned p0 t) = rewrap $ Factorial.spanMaybe (s0, p0) f' t
      where f' (s, p) prime = do s' <- f s (OffsetPositioned p prime)
                                 let p' = succ p
                                 Just $! seq p' (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   spanMaybe' s0 f (OffsetPositioned p0 t) = rewrap $! Factorial.spanMaybe' (s0, p0) f' t
      where f' (s, p) prime = do s' <- f s (OffsetPositioned p prime)
                                 let p' = succ p
                                 Just $! s' `seq` p' `seq` (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   span f (OffsetPositioned p0 t) = rewrap $ Factorial.spanMaybe' p0 f' t
      where f' p prime = if f (OffsetPositioned p prime)
                         then Just $! succ p
                         else Nothing
            rewrap (prefix, suffix, p) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix)
   splitAt n m@(OffsetPositioned p c) | n <= 0 = (mempty, m)
                                      | n >= length c = (m, mempty)
                                      | otherwise = (OffsetPositioned p prefix, OffsetPositioned (p + n) suffix)
      where (prefix, suffix) = splitAt n c
   drop n (OffsetPositioned p c) = OffsetPositioned (p + n) (Factorial.drop n c)
   take n (OffsetPositioned p c) = OffsetPositioned p (Factorial.take n c)
   {-# INLINE splitPrimePrefix #-}
   {-# INLINE splitPrimeSuffix #-}
   {-# INLINE span #-}
   {-# INLINE splitAt #-}
   {-# INLINE take #-}
   {-# INLINE drop #-}

instance (StableFactorial m, TextualMonoid m) => Factorial (LinePositioned m) where
   factors (LinePositioned p0 l0 lp0 c) = snd $ List.mapAccumL next (p0, l0, lp0) (factors c)
      where next (p, l, lp) c1 = let p' = succ p
                                 in p' `seq` case characterPrefix c1
                                             of Just '\n' -> ((p', succ l, p), LinePositioned p l lp c1)
                                                Just '\f' -> ((p', succ l, p), LinePositioned p l lp c1)
                                                Just '\r' -> ((p', l, p), LinePositioned p l lp c1)
                                                Just '\t' -> ((p', l, lp + (p - lp) `mod` 8 - 8),
                                                              LinePositioned p l lp c1)
                                                Just ch | isZeroWidth ch -> ((p, l, lp), LinePositioned p l lp c1)
                                                _ -> ((p', l, lp), LinePositioned p l lp c1)
   primePrefix (LinePositioned p l lp c) = LinePositioned p l lp (primePrefix c)
   foldl f a0 (LinePositioned p0 l0 lp0 c0) = fstOf4 $! Factorial.foldl f' (a0, p0, l0, lp0) c0
      where f' (a, p, l, lp) c = case characterPrefix c
                                 of Just '\n' -> (f a (LinePositioned p l lp c), succ p, succ l, p)
                                    Just '\f' -> (f a (LinePositioned p l lp c), succ p, succ l, p)
                                    Just '\r' -> (f a (LinePositioned p l lp c), succ p, l, p)
                                    Just '\t' -> (f a (LinePositioned p l lp c), succ p, l, lp + (p - lp) `mod` 8 - 8)
                                    Just ch | isZeroWidth ch -> (f a (LinePositioned p l lp c), p, l, lp)
                                    _ -> (f a (LinePositioned p l lp c), succ p, l, lp)
   foldl' f a0 (LinePositioned p0 l0 lp0 c0) = fstOf4 $! Factorial.foldl' f' (a0, p0, l0, lp0) c0
      where f' (a, p, l, lp) c = let a' = f a (LinePositioned p l lp c)
                                 in seq a' (case characterPrefix c
                                            of Just '\n' -> (a', succ p, succ l, p)
                                               Just '\f' -> (a', succ p, succ l, p)
                                               Just '\r' -> (a', succ p, l, p)
                                               Just '\t' -> (a', succ p, l, lp + (p - lp) `mod` 8 - 8)
                                               Just ch | isZeroWidth ch -> (a', p, l, lp)
                                               _ -> (a', succ p, l, lp))
   foldr f a0 (LinePositioned p0 l0 lp0 c0) = Factorial.foldr f' (const3 a0) c0 p0 l0 lp0
      where f' c cont p l lp = case characterPrefix c
                               of Just '\n' -> f (LinePositioned p l lp c) $ ((cont $! succ p) $! succ l) p
                                  Just '\f' -> f (LinePositioned p l lp c) $ ((cont $! succ p) $! succ l) p
                                  Just '\r' -> f (LinePositioned p l lp c) $ (cont $! succ p) l p
                                  Just '\t' -> f (LinePositioned p l lp c) $ (cont $! succ p) l
                                               $! lp + (p - lp) `mod` 8 - 8
                                  Just ch | isZeroWidth ch -> f (LinePositioned p l lp c) $ (cont p) l lp
                                  _ -> f (LinePositioned p l lp c) $ (cont $! succ p) l lp
   foldMap f (LinePositioned p0 l0 lp0 c) = appEndo (Factorial.foldMap f' c) (const mempty) p0 l0 lp0
      where -- f' :: m -> Endo (Int -> Int -> Int -> m)
            f' prime = Endo (\cont p l lp-> f (LinePositioned p l lp prime)
                                            `mappend`
                                            case characterPrefix prime
                                            of Just '\n' -> cont (succ p) (succ l) p
                                               Just '\f' -> cont (succ p) (succ l) p
                                               Just '\r' -> cont (succ p) l p
                                               Just '\t' -> cont (succ p) l (lp + (p - lp) `mod` 8 - 8)
                                               Just ch | isZeroWidth ch -> cont p l lp
                                               _ -> cont (succ p) l lp)
   length = length . extractLines
   reverse (LinePositioned p l lp c) = LinePositioned p l lp (Factorial.reverse c)
   {-# INLINE primePrefix #-}
   {-# INLINE foldl #-}
   {-# INLINE foldl' #-}
   {-# INLINE foldr #-}
   {-# INLINE foldMap #-}
   {-# INLINE length #-}
   {-# INLINE reverse #-}

instance (StableFactorial m, TextualMonoid m) => FactorialMonoid (LinePositioned m) where
   splitPrimePrefix (LinePositioned p l lp c) = fmap rewrap (splitPrimePrefix c)
      where rewrap (cp, cs) = (LinePositioned p l lp cp,
                               if null cs then mempty
                               else case characterPrefix cp
                                    of Just '\n' -> LinePositioned p' (succ l) p cs
                                       Just '\f' -> LinePositioned p' (succ l) p cs
                                       Just '\r' -> LinePositioned p' l p cs
                                       Just '\t' -> LinePositioned p' l (lp + (p - lp) `mod` 8 - 8) cs
                                       Just ch | isZeroWidth ch -> LinePositioned p l lp cs
                                       _ -> LinePositioned p' l lp cs)
            p' = succ p
   splitPrimeSuffix (LinePositioned p l lp c) = fmap rewrap (splitPrimeSuffix c)
      where rewrap (cp, cs) = (LinePositioned p l lp cp, LinePositioned p' (l + lines) (p' - columns) cs)
               where len = length cp
                     (lines, columns) = linesColumns cp
                     p' = p + len
   spanMaybe s0 f (LinePositioned p0 l0 lp0 c) = rewrap $ Factorial.spanMaybe (s0, p0, l0, lp0) f' c
      where f' (s, p, l, lp) prime = do s' <- f s (LinePositioned p l lp prime)
                                        let p' = succ p
                                            l' = succ l
                                        Just $! p' `seq` case characterPrefix prime
                                                         of Just '\n' -> l' `seq` (s', p', l', p)
                                                            Just '\f' -> l' `seq` (s', p', l', p)
                                                            Just '\r' -> (s', p', l, p)
                                                            Just '\t' -> (s', p', l, lp + (p - lp) `mod` 8 - 8)
                                                            Just ch | isZeroWidth ch -> (s', p, l, lp)
                                                            _ -> (s', p', l, lp)
            rewrap (prefix, suffix, (s, p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix, s)
   spanMaybe' s0 f (LinePositioned p0 l0 lp0 c) = rewrap $! Factorial.spanMaybe' (s0, p0, l0, lp0) f' c
      where f' (s, p, l, lp) prime = do s' <- f s (LinePositioned p l lp prime)
                                        let p' = succ p
                                            l' = succ l
                                        Just $! s' `seq` p' `seq` case characterPrefix prime
                                                                  of Just '\n' -> l' `seq` (s', p', l', p)
                                                                     Just '\f' -> l' `seq` (s', p', l', p)
                                                                     Just '\r' -> (s', p', l, p)
                                                                     Just '\t' -> (s', p', l, lp + (p - lp) `mod` 8 - 8)
                                                                     Just ch | isZeroWidth ch -> (s', p, l, lp)
                                                                     _ -> (s', p', l, lp)
            rewrap (prefix, suffix, (s, p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix, s)

   span f (LinePositioned p0 l0 lp0 t) = rewrap $ Factorial.spanMaybe' (p0, l0, lp0) f' t
      where f' (p, l, lp) prime = if f (LinePositioned p l lp prime)
                                  then let p' = succ p
                                           l' = succ l
                                       in Just $! p' `seq` case characterPrefix prime
                                                           of Just '\n' -> l' `seq` (p', l', p)
                                                              Just '\f' -> l' `seq` (p', l', p)
                                                              Just '\r' -> (p', l, p)
                                                              Just '\t' -> (p', l, lp + (p - lp) `mod` 8 - 8)
                                                              Just c | isZeroWidth c -> (p, l, lp)
                                                              _ -> (p', l, lp)
                                  else Nothing
            rewrap (prefix, suffix, (p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix)
   splitAt n m@(LinePositioned p l lp c) | n <= 0 = (mempty, m)
                                         | n >= length c = (m, mempty)
                                         | otherwise = (LinePositioned p l lp prefix,
                                                        LinePositioned p' (l + lines) (p' - columns) suffix)
      where (prefix, suffix) = splitAt n c
            (lines, columns) = linesColumns prefix
            p' = p + n
   take n (LinePositioned p l lp c) = LinePositioned p l lp (Factorial.take n c)
   {-# INLINE splitPrimePrefix #-}
   {-# INLINE splitPrimeSuffix #-}
   {-# INLINE span #-}
   {-# INLINE splitAt #-}
   {-# INLINE take #-}

instance StableFactorial m => StableFactorial (OffsetPositioned m)

instance (StableFactorial m, TextualMonoid m) => StableFactorial (LinePositioned m)

instance IsString m => IsString (OffsetPositioned m) where
   fromString = pure . fromString

instance IsString m => IsString (LinePositioned m) where
   fromString = pure . fromString

instance (StableFactorial m, TextualMonoid m) => TextualMonoid (OffsetPositioned m) where
   splitCharacterPrefix (OffsetPositioned p t) = fmap rewrap (splitCharacterPrefix t)
      where rewrap (c, cs) = if null cs then (c, mempty) else (c, OffsetPositioned (succ p) cs)

   fromText = pure . fromText
   singleton = pure . singleton

   characterPrefix = characterPrefix . extractOffset

   map f (OffsetPositioned p c) = OffsetPositioned p (map f c)
   concatMap f (OffsetPositioned p c) = OffsetPositioned p (concatMap (extractOffset . f) c)
   all p = all p . extractOffset
   any p = any p . extractOffset

   foldl ft fc a0 (OffsetPositioned p0 c0) = fst $ Textual.foldl ft' fc' (a0, p0) c0
      where ft' (a, p) c = (ft a (OffsetPositioned p c), succ p)
            fc' (a, p) c = (fc a c, succ p)
   foldl' ft fc a0 (OffsetPositioned p0 c0) = fst $ Textual.foldl' ft' fc' (a0, p0) c0
      where ft' (a, p) c = ((,) $! ft a (OffsetPositioned p c)) $! succ p
            fc' (a, p) c = ((,) $! fc a c) $! succ p
   foldr ft fc a0 (OffsetPositioned p0 c0) = snd $ Textual.foldr ft' fc' (p0, a0) c0
      where ft' c (p, a) = (succ p, ft (OffsetPositioned p c) a)
            fc' c (p, a) = (succ p, fc c a)

   scanl f ch (OffsetPositioned p c) = OffsetPositioned p (Textual.scanl f ch c)
   scanl1 f (OffsetPositioned p c) = OffsetPositioned p (Textual.scanl1 f c)
   scanr f ch (OffsetPositioned p c) = OffsetPositioned p (Textual.scanr f ch c)
   scanr1 f (OffsetPositioned p c) = OffsetPositioned p (Textual.scanr1 f c)
   mapAccumL f a0 (OffsetPositioned p c) = fmap (OffsetPositioned p) (Textual.mapAccumL f a0 c)
   mapAccumR f a0 (OffsetPositioned p c) = fmap (OffsetPositioned p) (Textual.mapAccumR f a0 c)

   spanMaybe s0 ft fc (OffsetPositioned p0 t) = rewrap $ Textual.spanMaybe (s0, p0) ft' fc' t
      where ft' (s, p) prime = do s' <- ft s (OffsetPositioned p prime)
                                  let p' = succ p
                                  Just $! seq p' (s', p')
            fc' (s, p) c = do s' <- fc s c
                              let p' = succ p
                              Just $! seq p' (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   spanMaybe' s0 ft fc (OffsetPositioned p0 t) = rewrap $! Textual.spanMaybe' (s0, p0) ft' fc' t
      where ft' (s, p) prime = do s' <- ft s (OffsetPositioned p prime)
                                  let p' = succ p
                                  Just $! s' `seq` p' `seq` (s', p')
            fc' (s, p) c = do s' <- fc s c
                              let p' = succ p
                              Just $! s' `seq` p' `seq` (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   span ft fc (OffsetPositioned p0 t) = rewrap $ Textual.spanMaybe' p0 ft' fc' t
      where ft' p prime = if ft (OffsetPositioned p prime)
                          then Just $! succ p
                          else Nothing
            fc' p c = if fc c
                      then Just $! succ p
                      else Nothing
            rewrap (prefix, suffix, p) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix)

   split f (OffsetPositioned p0 c0) = rewrap p0 (Textual.split f c0)
      where rewrap _ [] = []
            rewrap p (c:rest) = OffsetPositioned p c : rewrap (p + length c) rest
   find p = find p . extractOffset

   foldl_ fc a0 (OffsetPositioned _ c) = Textual.foldl_ fc a0 c
   foldl_' fc a0 (OffsetPositioned _ c) = Textual.foldl_' fc a0 c
   foldr_ fc a0 (OffsetPositioned _ c) = Textual.foldr_ fc a0 c

   spanMaybe_ s0 fc (OffsetPositioned p0 t) = rewrap $ Textual.spanMaybe_' (s0, p0) fc' t
      where fc' (s, p) c = do s' <- fc s c
                              let p' = succ p
                              Just $! seq p' (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   spanMaybe_' s0 fc (OffsetPositioned p0 t) = rewrap $! Textual.spanMaybe_' (s0, p0) fc' t
      where fc' (s, p) c = do s' <- fc s c
                              let p' = succ p
                              Just $! s' `seq` p' `seq` (s', p')
            rewrap (prefix, suffix, (s, p)) = (OffsetPositioned p0 prefix, OffsetPositioned p suffix, s)
   span_ bt fc (OffsetPositioned p0 t) = rewrap $ Textual.span_ bt fc t
      where rewrap (prefix, suffix) = (OffsetPositioned p0 prefix, OffsetPositioned (p0 + length prefix) suffix)
   break_ bt fc (OffsetPositioned p0 t) = rewrap $ Textual.break_ bt fc t
      where rewrap (prefix, suffix) = (OffsetPositioned p0 prefix, OffsetPositioned (p0 + length prefix) suffix)
   dropWhile_ bt fc t = snd (span_ bt fc t)
   takeWhile_ bt fc (OffsetPositioned p t) = OffsetPositioned p (takeWhile_ bt fc t)
   toString ft (OffsetPositioned _ t) = toString (ft . pure) t
   toText ft (OffsetPositioned _ t) = toText (ft . pure) t

   {-# INLINE characterPrefix #-}
   {-# INLINE splitCharacterPrefix #-}
   {-# INLINE map #-}
   {-# INLINE concatMap #-}
   {-# INLINE foldl' #-}
   {-# INLINE foldr #-}
   {-# INLINE spanMaybe' #-}
   {-# INLINE span #-}
   {-# INLINE foldl_' #-}
   {-# INLINE foldr_ #-}
   {-# INLINE any #-}
   {-# INLINE all #-}
   {-# INLINE spanMaybe_' #-}
   {-# INLINE span_ #-}
   {-# INLINE break_ #-}
   {-# INLINE dropWhile_ #-}
   {-# INLINE takeWhile_ #-}
   {-# INLINE split #-}
   {-# INLINE find #-}

instance (StableFactorial m, TextualMonoid m) => TextualMonoid (LinePositioned m) where
   splitCharacterPrefix (LinePositioned p l lp t) =
      case splitCharacterPrefix t
      of Nothing -> Nothing
         Just (c, rest) | null rest -> Just (c, mempty)
         Just ('\n', rest) -> Just ('\n', LinePositioned p' (succ l) p rest)
         Just ('\f', rest) -> Just ('\f', LinePositioned p' (succ l) p rest)
         Just ('\r', rest) -> Just ('\r', LinePositioned p' l p rest)
         Just ('\t', rest) -> Just ('\t', LinePositioned p' l (lp + (p - lp) `mod` 8 - 8) rest)
         Just (ch, rest)
            | isZeroWidth ch -> Just (ch, LinePositioned p l lp rest)
            | otherwise -> Just (ch, LinePositioned p' l lp rest)
      where p' = succ p

   fromText = pure . fromText
   singleton = pure . singleton

   characterPrefix = characterPrefix . extractLines

   map f (LinePositioned p l lp c) = LinePositioned p l lp (map f c)
   concatMap f (LinePositioned p l lp c) = LinePositioned p l lp (concatMap (extractLines . f) c)
   all p = all p . extractLines
   any p = any p . extractLines

   foldl ft fc a0 (LinePositioned p0 l0 lp0 c0) = fstOf4 $ Textual.foldl ft' fc' (a0, p0, l0, lp0) c0
      where ft' (a, p, l, lp) c = (ft a (LinePositioned p l lp c), succ p, l, lp)
            fc' (a, p, l, _lp) '\n' = (fc a '\n', succ p, succ l, p)
            fc' (a, p, l, _lp) '\f' = (fc a '\f', succ p, succ l, p)
            fc' (a, p, l, _lp) '\r' = (fc a '\r', succ p, l, p)
            fc' (a, p, l, lp) '\t' = (fc a '\t', succ p, l, lp + (p - lp) `mod` 8 - 8)
            fc' (a, p, l, lp) c
               | isZeroWidth c = (fc a c, p, l, lp)
               | otherwise = (fc a c, succ p, l, lp)
   foldl' ft fc a0 (LinePositioned p0 l0 lp0 c0) = fstOf4 $ Textual.foldl' ft' fc' (a0, p0, l0, lp0) c0
      where ft' (a, p, l, lp) c = let a' = ft a (LinePositioned p l lp c)
                                      p' = succ p
                                  in a' `seq` p' `seq` (a', p', l, lp)
            fc' (a, p, l, lp) c = let a' = fc a c
                                      p' = succ p
                                      l' = succ l
                                  in a' `seq` p' `seq` case c
                                                       of '\n' -> l' `seq` (a', p', l', p)
                                                          '\f' -> l' `seq` (a', p', l', p)
                                                          '\r' -> (a', p', l, p)
                                                          '\t' -> (a', p', l, lp + (p - lp) `mod` 8 - 8)
                                                          _ | isZeroWidth c -> (a', p, l, lp)
                                                          _ -> (a', p', l, lp)
   foldr ft fc a0 (LinePositioned p0 l0 lp0 c0) = Textual.foldr ft' fc' (const3 a0) c0 p0 l0 lp0
      where ft' c cont p l lp = ft (LinePositioned p l lp c) $ (cont $! succ p) l lp
            fc' c cont p l lp
               | c == '\n' = fc c $ ((cont $! succ p) $! succ l) p
               | c == '\f' = fc c $ ((cont $! succ p) $! succ l) p
               | c == '\r' = fc c $ (cont $! succ p) l p
               | c == '\t' = fc c $ (cont $! succ p) l (lp + (p - lp) `mod` 8 - 8)
               | isZeroWidth c = fc c $ (cont p) l lp
               | otherwise = fc c $ (cont $! succ p) l lp

   spanMaybe s0 ft fc (LinePositioned p0 l0 lp0 t) = rewrap $ Textual.spanMaybe (s0, p0, l0, lp0) ft' fc' t
      where ft' (s, p, l, lp) prime = do s' <- ft s (LinePositioned p l lp prime)
                                         let p' = succ p
                                         Just $! seq p' (s', p', l, lp)
            fc' (s, p, l, lp) c =
               fc s c
               >>= \s'-> Just $! seq p' (if c == '\n' || c == '\f' then seq l' (s', p', l', p)
                                         else if c == '\r' then (s', p', l, p)
                                         else if c == '\t' then (s', p', l, lp + (p - lp) `mod` 8 - 8)
                                         else if isZeroWidth c then (s', p, l, lp)
                                         else (s', p', l, lp))
               where p' = succ p
                     l' = succ l
            rewrap (prefix, suffix, (s, p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix, s)
   spanMaybe' s0 ft fc (LinePositioned p0 l0 lp0 t) = rewrap $! Textual.spanMaybe' (s0, p0, l0, lp0) ft' fc' t
      where ft' (s, p, l, lp) prime = do s' <- ft s (LinePositioned p l lp prime)
                                         let p' = succ p
                                         Just $! s' `seq` p' `seq` (s', p', l, lp)
            fc' (s, p, l, lp) c = do s' <- fc s c
                                     let p' = succ p
                                         l' = succ l
                                     Just $! s' `seq` p'
                                             `seq` (if c == '\n' || c == '\f' then seq l' (s', p', l', p)
                                                    else if c == '\r' then (s', p', l, p)
                                                    else if c == '\t' then (s', p', l, lp + (p - lp) `mod` 8 - 8)
                                                    else if isZeroWidth c then (s', p, l, lp)
                                                    else (s', p', l, lp))
            rewrap (prefix, suffix, (s, p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix, s)
   span ft fc (LinePositioned p0 l0 lp0 t) = rewrap $ Textual.spanMaybe' (p0, l0, lp0) ft' fc' t
      where ft' (p, l, lp) prime = if ft (LinePositioned p l lp prime)
                                   then let p' = succ p
                                        in p' `seq` Just (p', l, lp)
                                   else Nothing
            fc' (p, l, lp) c | fc c = Just $! seq p'
                                      $ if c == '\n' || c == '\f' then seq l' (p', l', p)
                                        else if c == '\r' then (p', l, p)
                                        else if c == '\t' then (p', l, lp + (p - lp) `mod` 8 - 8)
                                        else if isZeroWidth c then (p, l, lp)
                                        else (p', l, lp)
                             | otherwise = Nothing
               where p' = succ p
                     l' = succ l
            rewrap (prefix, suffix, (p, l, lp)) = (LinePositioned p0 l0 lp0 prefix, LinePositioned p l lp suffix)

   scanl f ch (LinePositioned p l lp c) = LinePositioned p l lp (Textual.scanl f ch c)
   scanl1 f (LinePositioned p l lp c) = LinePositioned p l lp (Textual.scanl1 f c)
   scanr f ch (LinePositioned p l lp c) = LinePositioned p l lp (Textual.scanr f ch c)
   scanr1 f (LinePositioned p l lp c) = LinePositioned p l lp (Textual.scanr1 f c)
   mapAccumL f a0 (LinePositioned p l lp c) = fmap (LinePositioned p l lp) (Textual.mapAccumL f a0 c)
   mapAccumR f a0 (LinePositioned p l lp c) = fmap (LinePositioned p l lp) (Textual.mapAccumR f a0 c)

   split f (LinePositioned p0 l0 lp0 c0) = rewrap p0 l0 lp0 (Textual.split f c0)
      where rewrap _ _ _ [] = []
            rewrap p l lp (c:rest) = LinePositioned p l lp c
                                     : rewrap p' (l + lines) (if lines == 0 then lp else p' - columns) rest
               where p' = p + length c
                     (lines, columns) = linesColumns c
   find p = find p . extractLines

   foldl_ fc a0 (LinePositioned _ _ _ t) = Textual.foldl_ fc a0 t
   foldl_' fc a0 (LinePositioned _ _ _ t) = Textual.foldl_' fc a0 t
   foldr_ fc a0 (LinePositioned _ _ _ t) = Textual.foldr_ fc a0 t

   spanMaybe_ s0 fc (LinePositioned p0 l0 lp0 t) = rewrap $ Textual.spanMaybe_ s0 fc t
      where rewrap (prefix, suffix, s) = (LinePositioned p0 l0 lp0 prefix,
                                          LinePositioned p1 (l0 + l) (if l == 0 then lp0 else p1 - col) suffix,
                                          s)
              where (l, col) = linesColumns prefix
                    p1 = p0 + length prefix
   spanMaybe_' s0 fc (LinePositioned p0 l0 lp0 t) = rewrap $ Textual.spanMaybe_' s0 fc t
      where rewrap (prefix, suffix, s) = p1 `seq` l1 `seq` lp1 `seq`
                                         (LinePositioned p0 l0 lp0 prefix, LinePositioned p1 l1 lp1 suffix, s)
              where (l, col) = linesColumns' prefix
                    p1 = p0 + length prefix
                    l1 = l0 + l
                    lp1 = if l == 0 then lp0 else p1 - col
   span_ bt fc (LinePositioned p0 l0 lp0 t) = rewrap $ Textual.span_ bt fc t
      where rewrap (prefix, suffix) = (LinePositioned p0 l0 lp0 prefix,
                                       LinePositioned p1 (l0 + l) (if l == 0 then lp0 else p1 - col) suffix)
              where (l, col) = linesColumns' prefix
                    p1 = p0 + length prefix
   break_ bt fc t = span_ (not bt) (not . fc) t
   dropWhile_ bt fc t = snd (span_ bt fc t)
   takeWhile_ bt fc (LinePositioned p l lp t) = LinePositioned p l lp (takeWhile_ bt fc t)
   toString ft lpt = toString (ft . pure) (extractLines lpt)
   toText ft lpt = toText (ft . pure) (extractLines lpt)

   {-# INLINE characterPrefix #-}
   {-# INLINE splitCharacterPrefix #-}
   {-# INLINE map #-}
   {-# INLINE concatMap #-}
   {-# INLINE foldl' #-}
   {-# INLINE foldr #-}
   {-# INLINE spanMaybe' #-}
   {-# INLINE span #-}
   {-# INLINE split #-}
   {-# INLINE find #-}
   {-# INLINE foldl_' #-}
   {-# INLINE foldr_ #-}
   {-# INLINE any #-}
   {-# INLINE all #-}
   {-# INLINE spanMaybe_' #-}
   {-# INLINE span_ #-}
   {-# INLINE break_ #-}
   {-# INLINE dropWhile_ #-}
   {-# INLINE takeWhile_ #-}

linesColumns :: TextualMonoid m => m -> (Int, Int)
linesColumns t = Textual.foldl (const . fmap succ) fc (0, 1) t
   where fc (l, _) '\n' = (succ l, 1)
         fc (l, _) '\f' = (succ l, 1)
         fc (l, _) '\r' = (l, 1)
         fc (l, c) '\t' = (l, c + 9 - c `mod` 8)
         fc (l, c) ch | isZeroWidth ch = (l, c)
         fc (l, c) _ = (l, succ c)
linesColumns' :: TextualMonoid m => m -> (Int, Int)
linesColumns' t = Textual.foldl' (const . fmap succ) fc (0, 1) t
   where fc (l, _) '\n' = let l' = succ l in seq l' (l', 1)
         fc (l, _) '\f' = let l' = succ l in seq l' (l', 1)
         fc (l, _) '\r' = (l, 1)
         fc (l, c) '\t' = (l, c + 9 - c `mod` 8)
         fc (l, c) ch | isZeroWidth ch = (l, c)
         fc (l, c) _ = let c' = succ c in seq c' (l, c')
{-# INLINE linesColumns #-}
{-# INLINE linesColumns' #-}

isZeroWidth :: Char -> Bool
isZeroWidth '\x200b' = True  -- zero width space
isZeroWidth '\x200c' = True  -- zero width non-joiner
isZeroWidth '\x200d' = True  -- zero width joiner
isZeroWidth '\xfeff' = True  -- zero width no-break space
isZeroWidth _ = False

const3 :: a -> b -> c -> d -> a
const3 a _p _l _lp = a
{-# INLINE const3 #-}

fstOf4 :: (a, b, c, d) -> a
fstOf4 (a, _, _, _) = a
{-# INLINE fstOf4  #-}
