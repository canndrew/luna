{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-unused-foralls #-}

module Luna.IR.Term.Core where

import Prologue

import qualified Data.Graph.Component.Layer.Class  as Layer
import qualified Data.Graph.Component.Layer.Layout as Layout
import qualified Luna.IR.Term.Format         as Format
import qualified OCI.IR.Link                 as Link
import qualified OCI.IR.Term.Construction    as Term
import qualified OCI.IR.Term.Definition      as Term
import qualified OCI.IR.Term.Layer           as Layer

import Data.PtrList.Mutable         (UnmanagedPtrList)
import Data.Vector.Storable.Foreign (Vector)
import OCI.Data.Name                (Name)
import OCI.IR.Term.Class            (Term, Terms)
import OCI.IR.Term.Definition       (LinkTo, LinksTo)
import OCI.IR.Term.Layout           ()



----------------
-- === IR === --
----------------

-- | Core IR terms definition. For more information on what the actual data
--   is created please refer to the documentation of the 'Term.define' function.

-- === IR Atoms === ---

Term.define [d|

 data Value
    = App     { base :: LinkTo Terms, arg   :: LinkTo Terms                    }
    | Cons    { name :: Name        , args  :: LinksTo Terms                   }
    | Top_

 data Thunk
    = Acc     { base :: LinkTo Terms, name  :: Name                            }
    | Lam     { arg  :: LinkTo Terms, body  :: LinkTo Terms                    }
    | Match   { arg  :: LinkTo Terms, ways  :: LinksTo Terms                   }
    | Update  { base :: LinkTo Terms, path  :: Vector Name, val :: LinkTo Terms}

 data Phrase
    = Blank
    | Missing
    | Unify   { left :: LinkTo Terms, right :: LinkTo Terms                    }

 data Draft
    = Var     { name :: Name                                                   }

 |]

-- === Smart constructors === --

-- | The smart constructor of 'Top' is special one, because its type link loops
--   to itself. All other smart constructors use 'top' as their initial type
--   representation.
top :: Term.Creator Top m => m (Term Top)
top = Term.uncheckedUntypedNewM $ \self -> do
    typeLink <- Link.new self self
    Layer.write @Layer.Type self (Layout.relayout typeLink)
    pure Top
{-# INLINE top #-}
