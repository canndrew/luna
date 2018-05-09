{-# LANGUAGE OverloadedStrings #-}

module Luna.Debug.IR.Visualizer where

import Prologue

import qualified Control.Lens.Aeson          as Lens
import qualified Control.Monad.State         as State
import qualified Data.Aeson                  as Aeson
import qualified Data.ByteString.Lazy.Char8  as ByteString
import qualified Data.Graph.Data.Layer.Layout as IR
import qualified Data.Map                    as Map
import qualified Data.Set                    as Set
import qualified Data.Tag                    as Tag
import qualified Luna.IR                     as IR
import qualified Luna.IR.Layer               as Layer
import qualified Luna.Pass                   as Pass
import qualified System.Environment          as System
import qualified Web.Browser                 as Browser

import Data.Map (Map)
import Data.Set (Set)



---------------------------
-- === IR Visualizer === --
---------------------------

-- === Definitions === --

type NodeId = Int

data Node = Node
    { __label  :: Text
    , __styles :: [Text]
    , __id     :: NodeId
    } deriving (Generic, Show)
makeLenses ''Node

data Edge = Edge
    { __src    :: NodeId
    , __dst    :: NodeId
    , __styles :: [Text]
    } deriving (Generic, Show)
makeLenses ''Edge

data Graph = Graph
    { __nodes :: [Node]
    , __edges :: [Edge]
    } deriving (Generic, Show)
makeLenses ''Graph

type MonadVis m =
    ( MonadIO m
    , Layer.Reader IR.Term IR.Model  m
    , Layer.Reader IR.Term IR.Type   m
    , Layer.Reader IR.Link IR.Source m
    )


-- === Private API === --

gatherNodesFrom :: MonadVis m => IR.Term layout -> m (Set IR.SomeTerm)
gatherNodesFrom root = State.execStateT (go $ IR.relayout root) def where
    go (root :: IR.SomeTerm) = do
        visited <- State.gets $ Set.member root
        when_ (not visited) $ do
            model <- Layer.read @IR.Model root
            inps  <- traverse IR.source =<< IR.inputs root
            tp    <- IR.source =<< Layer.read @IR.Type root
            State.modify $ Set.insert root
            traverse_ (go . IR.relayout) inps
            go $ IR.relayout tp

buildVisualizationGraph :: MonadVis m => IR.Term layout -> m Graph
buildVisualizationGraph root = do
    allNodes <- gatherNodesFrom root
    let nodesWithIds = Map.fromList $ zip (Set.toList allNodes) [1..]
    visNodes <- traverse (buildVisualizationNode nodesWithIds)
              $ Map.keys nodesWithIds
    pure $ Graph (fst <$> visNodes) (concat $ snd <$> visNodes)


buildVisualizationNode :: MonadVis m
    => Map IR.SomeTerm NodeId -> IR.SomeTerm -> m (Node, [Edge])
buildVisualizationNode idsMap ref = do
    model <- Layer.read @IR.Model ref
    inps  <- traverse IR.source =<< IR.inputs ref
    tp    <- IR.source =<< Layer.read @IR.Type ref
    let getNodeId :: ∀ layout. IR.Term layout -> NodeId
        getNodeId = unsafeFromJust . flip Map.lookup idsMap . IR.relayout
        tgtId     = getNodeId ref
        tag       = IR.showTag model
        tpEdge    = Edge (getNodeId tp) tgtId ["type"]
        inpEdges  = (\n -> Edge (getNodeId n) tgtId ["input"]) <$> inps
    pure (Node tag [tag] tgtId, tpEdge : inpEdges)


-- === Public API === --

displayVisualization :: MonadVis m => String -> IR.Term layout -> m ()
displayVisualization name root = do
    graph <- buildVisualizationGraph root
    let visData = ByteString.unpack $ Aeson.encode graph
    liftIO $ do
        dataPath  <- System.lookupEnv "VIS_DATA_PATH"
        visUriEnv <- System.lookupEnv "VIS_URI"
        let visUri = fromJust "http://localhost:8000" visUriEnv
        for_ dataPath $ \path -> do
            writeFile (path <> "/" <> name <> ".json") visData
            Browser.openBrowser $ visUri <> "?cfgPath=" <> name


-- === Instances === --

instance Aeson.ToJSON Node  where toEncoding = Lens.toEncoding
instance Aeson.ToJSON Edge  where toEncoding = Lens.toEncoding
instance Aeson.ToJSON Graph where toEncoding = Lens.toEncoding