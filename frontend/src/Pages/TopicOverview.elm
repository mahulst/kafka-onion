module Pages.TopicOverview exposing (Model, Msg(..), update, view)

import Element
import Element.Border
import Element.Font
import Http
import RemoteData exposing (RemoteData(..))
import Routes exposing (getViewTopicPath)
import Shared exposing (Config, getLinkStyle, viewHttpError)
import Topic exposing (Topic)


type alias Model =
    { topicsResponse : RemoteData Http.Error (List Topic)
    }


type Msg
    = TopicsResponse (RemoteData Http.Error (List Topic))


update : Config -> Msg -> Model -> ( Model, Cmd Msg )
update config msg model =
    case msg of
        TopicsResponse response ->
            let
                newModel =
                    { topicsResponse = response }
            in
            ( newModel
            , Cmd.none
            )


view : Model -> Element.Element Msg
view model =
    let
        body =
            case model.topicsResponse of
                NotAsked ->
                    Element.el [] (Element.text "This should not have happened...")

                Success topics ->
                    viewTopicList (sortTopicList topics)

                Failure error ->
                    viewHttpError error

                Loading ->
                    Element.el [] (Element.text "Loading...")
    in
    Element.column [ Element.width Element.fill ]
        [ Element.row
            [ Element.paddingEach
                { top = 100
                , bottom = 16
                , left = 0
                , right = 0
                }
            , Element.centerX
            , Element.centerY
            ]
            [ Element.el [ Element.Font.size 62 ] (Element.text "All topics") ]
        , Element.row [ Element.width Element.fill ] [ body ]
        ]


sortTopicList : List Topic -> List Topic
sortTopicList list =
    List.sortBy .name list


viewTopicList : List Topic -> Element.Element Msg
viewTopicList topics =
    let
        viewRow : Topic -> Element.Element Msg
        viewRow =
            \topic ->
                Element.row
                    [ Element.width Element.fill
                    , Element.Border.color (Element.rgb 0.95 0.95 0.95)
                    , Element.Border.solid
                    , Element.Border.widthEach
                        { top = 1
                        , bottom = 0
                        , right = 0
                        , left = 0
                        }
                    , Element.paddingEach
                        { top = 12
                        , bottom = 24
                        , right = 0
                        , left = 0
                        }
                    ]
                    [ Element.link
                        ([] ++ getLinkStyle)
                        { url = getViewTopicPath topic.name
                        , label = Element.text topic.name
                        }
                    ]
    in
    Element.column [ Element.width Element.fill ] (List.map viewRow topics)
