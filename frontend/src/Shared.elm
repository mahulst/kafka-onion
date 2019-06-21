module Shared exposing (Flags, viewHttpError, getLinkStyle)

import Element
import Element.Background
import Element.Font
import Http
type alias Flags =
    { apiUrl : String }


viewHttpError : Http.Error -> Element.Element msg
viewHttpError error =
    let
        message =
            case error of
                Http.BadUrl str ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Something is wrong with the url:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text str) ]
                    ]

                Http.Timeout ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Request timed out!") ] ]

                Http.NetworkError ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Network error!") ] ]

                Http.BadStatus status ->
                    [ Element.paragraph [] [ Element.el [] (Element.text ("Got status code [" ++ String.fromInt status ++ "]")) ] ]

                Http.BadBody body ->
                    [ Element.paragraph [] [ Element.el [] (Element.text "Got unexpected body:") ]
                    , Element.paragraph [] [ Element.el [] (Element.text body) ]
                    ]
    in
    Element.column [ Element.width Element.fill, Element.Background.color (Element.rgb 0.7 0.4 0.4), Element.padding 24 ]
        [ Element.el
            []
            (Element.textColumn [ Element.width Element.fill ] message)
        ]


getLinkStyle =
    [ Element.Font.bold, Element.Font.color (Element.rgb 0.06 0.5 0.8) ]

