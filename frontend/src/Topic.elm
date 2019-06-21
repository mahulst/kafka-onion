module Topic exposing
    ( PartitionDetail
    , PartitionOffsets
    , Topic
    , TopicDetail
    , TopicMessage
    , addToOffsets
    , decodeAndSortPartitionDetailList
    , decodePartitionDetail
    , decodeTopic
    , decodeTopicDetail
    , decodeTopicMessage
    , decodeTopics
    )

import Dict exposing (Dict)
import Http
import Json.Decode as D
import Json.Decode.Extra as DExtra
import RemoteData exposing (RemoteData(..))


type alias Topic =
    { name : String
    , partitionCount : Int
    }


type alias PartitionOffsets =
    Dict Int Int


type alias TopicDetail =
    { name : String
    , partitionOffsets : PartitionOffsets
    , partitionDetails : List PartitionDetail
    }


type alias PartitionDetail =
    { id : Int
    , highwatermarkOffset : Int
    , messageCount : Int
    , messages : List TopicMessage
    }


type alias TopicMessage =
    { partition : Int
    , offset : Int
    , json : String
    }


addToOffsets : Int -> PartitionOffsets -> PartitionOffsets
addToOffsets n offsets =
    Dict.map (\_ offset -> offset + n) offsets


decodeTopic : D.Decoder Topic
decodeTopic =
    D.map2 Topic
        (D.field "name" D.string)
        (D.field "partition_count" D.int)


decodeTopics : D.Decoder (List Topic)
decodeTopics =
    D.list decodeTopic


decodeTopicDetail : D.Decoder TopicDetail
decodeTopicDetail =
    D.map3 TopicDetail
        (D.field "name" D.string)
        (D.field "partition_offsets" (DExtra.dict2 D.int D.int))
        decodeAndSortPartitionDetailList


decodeTopicMessage : D.Decoder TopicMessage
decodeTopicMessage =
    D.map3 TopicMessage
        (D.field "partition" D.int)
        (D.field "offset" D.int)
        (D.field "json" D.string)


decodeAndSortPartitionDetailList : D.Decoder (List PartitionDetail)
decodeAndSortPartitionDetailList =
    D.map (List.sortBy .id) (D.field "partition_details" (D.list decodePartitionDetail))


decodePartitionDetail : D.Decoder PartitionDetail
decodePartitionDetail =
    D.map4 PartitionDetail
        (D.field "id" D.int)
        (D.field "highwatermark_offset" D.int)
        (D.field "message_count" D.int)
        (D.field "messages" (D.list decodeTopicMessage))
