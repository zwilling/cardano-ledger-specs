{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Test.Shelley.Spec.Ledger.ConcreteCryptoTypes where

import Cardano.Crypto.DSIGN (MockDSIGN, VerKeyDSIGN)
import qualified Cardano.Crypto.DSIGN.Class as DSIGN
import Cardano.Crypto.Hash (MD5Prefix)
import Cardano.Crypto.KES (MockKES)
import qualified Cardano.Crypto.KES.Class as KES
import Cardano.Crypto.Util (SignableRepresentation)
import qualified Cardano.Crypto.VRF as VRF
import Cardano.Ledger.Crypto
import Cardano.Ledger.Shelley (ShelleyEra)
import Shelley.Spec.Ledger.API (PraosCrypto)
import Shelley.Spec.Ledger.BaseTypes (Seed)
import Test.Cardano.Crypto.VRF.Fake (FakeVRF)

-- | Mocking constraints used in generators
type Mock c =
  ( PraosCrypto c,
    KES.Signable (KES c) ~ SignableRepresentation,
    DSIGN.Signable (DSIGN c)
      ~ SignableRepresentation,
    VRF.Signable
      (VRF c)
      Seed
  )

-- | Additional mocking constraints used in examples.
type ExMock c =
  ( Mock c,
    Num (DSIGN.SignKeyDSIGN (DSIGN c)),
    Num (VerKeyDSIGN (DSIGN c)),
    (VRF c) ~ FakeVRF
  )

type C = ShelleyEra C_Crypto

data C_Crypto

instance Cardano.Ledger.Crypto.Crypto C_Crypto where
  type HASH C_Crypto = MD5Prefix 10
  type ADDRHASH C_Crypto = MD5Prefix 8
  type DSIGN C_Crypto = MockDSIGN
  type KES C_Crypto = MockKES 10
  type VRF C_Crypto = FakeVRF

instance PraosCrypto C_Crypto
